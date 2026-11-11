// Endgame activities, the PvP half and the bounty board: the guild siege (opcode 233, client game_siege), the ranked arena (236, game_arena), the
// battleground "Ember Wells" (200, game_battleground), the Scorched Marches (193, game_pvpzone) and the bounty board (223, game_bounty). The
// text and rules of siegemath.lua, arenatext.lua, bgview.lua, pvpzoneview.lua and bounty.lua are in the static view classes. The arena, the
// battleground and the Marches turn the secure mode off for the fight and back on after it (the main client's secureOff / secureRestore):
// the state classes raise Started and Ended, the app does the mode change.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    // ================================================================================================ Guild siege
    public static class SiegeView
    {
        public static string Countdown(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60, sec = s % 60;
            if (d > 0) return d + "d " + h + "h";
            if (h > 0) return h + "h " + m.ToString("00", CultureInfo.InvariantCulture) + "m";
            return m + "m " + sec.ToString("00", CultureInfo.InvariantCulture) + "s";
        }

        /// <summary>The teams by score, then kills, then name (an entry that is no object is left out).</summary>
        public static List<object> Sorted(object teams)
        {
            var list = new List<object>();
            if (teams is List<object> l) foreach (object o in l) if (o is Dictionary<string, object>) list.Add(o);
            list.Sort((a, b) =>
            {
                double sa = Json.Number(a, "score"), sb = Json.Number(b, "score");
                if (sa != sb) return sb.CompareTo(sa);
                double ka = Json.Number(a, "kills"), kb = Json.Number(b, "kills");
                if (ka != kb) return kb.CompareTo(ka);
                return string.CompareOrdinal(Json.Get(a, "name") is string na ? na : "nil", Json.Get(b, "name") is string nb ? nb : "nil");
            });
            return list;
        }

        public static string Holder(object data, out string color)
        {
            string phase = Json.Text(data, "phase");
            if (phase == "gather") { color = "#d6c9ae"; return Loc.T("Gates open in {0}", Eg.Clock(Json.Number(data, "left"))); }
            if (phase == "ending") { color = "#8c8070"; return Loc.T("The siege is over"); }
            string holder = Json.Text(data, "holder");
            if (holder.Length > 0) { color = Json.Text(data, "holderColor").Length > 0 ? Json.Text(data, "holderColor") : "#f6cf72"; return "Obelisk: " + holder; }
            if (Json.Truthy(data, "contested")) { color = "#e8582a"; return Loc.T("Obelisk: contested"); }
            color = "#8c8070";
            return Loc.T("Obelisk: neutral");
        }

        public static string Title(object data)
        {
            string phase = Json.Text(data, "phase");
            if (phase == "gather") return Loc.T("Guild Siege - gathering");
            if (phase == "ending")
            {
                string w = Json.Text(Json.Get(data, "result"), "winner");
                return w.Length > 0 ? w + " wins!" : Loc.T("Siege over");
            }
            if ((Json.Get(data, "brackets") is double b ? b : 1) > 1) return Loc.T("Guild Siege - arena {0}", Json.Get(data, "bracket") is double bd ? ((long)bd).ToString(CultureInfo.InvariantCulture) : Json.Text(data, "bracket"));
            return Loc.T("Guild Siege");
        }

        public static string YouText(object you)
            => !(you is Dictionary<string, object>) ? "" : Loc.T("You: {0} kills, {1} downed, {2} points", Json.Int(you, "kills"), Json.Int(you, "deaths"), Json.Int(you, "points"));
    }

    public sealed class SiegeState : EgModule
    {
        public const byte Opcode = 233;
        protected override byte Op => Opcode;

        public object Hud, Info;
        public double InfoAt;
        public bool Visible;

        public SiegeState(ExtOpcodes e) : base(e) { ext.On(Opcode, m => Handle(m.Action, Eg.DataOf(m))); }

        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void Show() { Visible = true; Send("open"); Changed(); }
        public void Hide() { Visible = false; }
        public void Join() { Send("join"); }
        public void Leave() { Send("leave"); }

        public void Handle(string action, object d)
        {
            if (action == "hud") Hud = d;
            else if (action == "hide") Hud = null;
            else if (action == "info")
            {
                Info = d; InfoAt = Now;
                if (Json.Truthy(d, "open")) Visible = true;
            }
            Changed();
        }

        /// <summary>The "Starts in ..." or "Running" text of the window.</summary>
        public string CountdownText(double nowMs)
        {
            if (Info == null) return "";
            if (Json.Text(Info, "phase") == "idle") return Loc.T("Starts in {0}", SiegeView.Countdown(Json.Number(Info, "inSeconds") - (nowMs - InfoAt) / 1000.0));
            return Loc.T("Running");
        }

        public void Clear() { Hud = Info = null; Visible = false; }
    }

    // ================================================================================================ Arena
    public static class ArenaText
    {
        public static string Result(string r, out string color)
        {
            color = r == "win" ? "#f6cf72" : r == "loss" ? "#e03a1e" : "#d6c9ae";
            return r == "win" ? "VICTORY" : r == "loss" ? "DEFEAT" : r == "draw" ? "DRAW" : (r ?? "?").ToUpperInvariant();
        }

        public static string ModeTitle(string mode) => mode == "1v1" ? "Duel 1v1" : mode == "2v2" ? "Team 2v2" : mode == "3v3" ? "Warband 3v3" : mode;

        public static string SeasonLine(object v, double seasonId, out string color, out string tip)
        {
            color = "#8c8070"; tip = "";
            if (!(v is Dictionary<string, object>)) return "";
            tip = Loc.T("PvP Season {0} rating {1} ({2} matches).", (long)(seasonId > 0 ? seasonId : 1), Json.Get(v, "rating") is double r ? (int)r : 1500, Json.Int(v, "matches"));
            if (!Json.Truthy(v, "placed"))
            {
                int total = Json.Int(v, "matches") + Json.Int(v, "placementLeft");
                return Loc.T("Season: placement {0}/{1}", Json.Int(v, "matches"), total);
            }
            color = Json.Text(v, "color").Length > 0 ? Json.Text(v, "color") : "#d6c9ae";
            return Loc.T("Season: {0} {1}", Json.Text(v, "tierName", "?"), Json.Get(v, "rating") is double rr ? (int)rr : 1500);
        }

        public static string SeasonDelta(object s)
        {
            if (!(s is Dictionary<string, object>)) return "";
            string text = Loc.T("Season {0} -> {1} ({2})", Json.Int(s, "before"), Json.Int(s, "after"), Eg.Delta(Json.Number(s, "delta")));
            if (Json.Truthy(s, "placed") && Json.Text(s, "tierName").Length > 0) text += " " + Json.Text(s, "tierName");
            else if (!Json.Truthy(s, "placed")) text += Loc.T(", placement: {0} left", Json.Int(s, "placementLeft"));
            return text;
        }

        public static string RatingLine(double before, double after, double delta) => Loc.T("Rating {0} -> {1} ({2})", (long)before, (long)after, Eg.Delta(delta));
        public static string Record(object r) => Json.Int(r, "wins") + "-" + Json.Int(r, "losses") + "-" + Json.Int(r, "draws");

        public static string Ago(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            if (s < 60) return Loc.T("just now");
            if (s < 3600) return s / 60 + "m ago";
            if (s < 86400) return s / 3600 + "h ago";
            return s / 86400 + "d ago";
        }

        public static string Reason(string r)
        {
            switch (r)
            {
                case "defeat": return "knock-out"; case "timeout": return "time ran out"; case "defeated": return "knocked out"; case "left": return "left the match";
                case "secure": return "secure mode on"; case "mc": return "multi-client"; case "stop": return "stopped"; default: return r ?? "";
            }
        }

        public static string HudCenter(string phase, double left, out string small)
        {
            if (phase == "countdown") { small = Loc.T("starts in"); return ((long)Math.Max(0, Math.Floor(left))).ToString(CultureInfo.InvariantCulture); }
            if (phase == "fight") { small = "fight"; return Eg.Clock(left); }
            small = "over";
            return "-";
        }

        public static string HpColor(double pct) => pct > 60 ? "#2f7a2a" : pct > 30 ? "#b07a10" : "#8a1010";
    }

    public sealed class ArenaState : EgModule
    {
        public const byte Opcode = 236;
        public const double ResultSeconds = 8;
        protected override byte Op => Opcode;
        public static readonly string[] Modes = { "1v1", "2v2", "3v3" };

        public object State, Hud, Result;
        public double StateAt, ResultUntil = -1;
        public bool Visible;
        public int MyTeam = 1;
        /// <summary>A match began (turn the secure mode off) or ended (cancel the attack, restore the mode).</summary>
        public Action Started = delegate { }, Ended = delegate { };

        public ArenaState(ExtOpcodes e) : base(e) { ext.On(Opcode, m => Handle(m.Action, Eg.DataOf(m))); }

        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void Show() { Visible = true; Send("open"); Changed(); }
        public void Hide() { Visible = false; }
        public bool Queue(string mode) { return Send("queue", D("mode", mode)); }
        public void LeaveQueue() { Send("leave"); }

        public bool InQueue => State != null && Json.Get(State, "queue") is Dictionary<string, object>;
        public bool InMatch => State != null && Json.Get(State, "match") is Dictionary<string, object>;
        public bool ResultShown(double nowMs) => Result != null && nowMs < ResultUntil;
        public bool HudShown(double nowMs) => Hud != null || ResultShown(nowMs);

        public void Handle(string action, object d)
        {
            switch (action)
            {
                case "state":
                    State = d; StateAt = Now;
                    if (Json.Truthy(d, "open")) Visible = true;
                    break;
                case "start":
                    MyTeam = Json.Get(d, "team") is double t ? (int)t : 1;
                    Visible = false; Result = null; ResultUntil = -1;
                    Started();
                    break;
                case "hud":
                    if (Result != null && Now < ResultUntil) break;   // the result is on screen
                    MyTeam = Json.Get(d, "team") is double tm ? (int)tm : MyTeam;
                    Hud = d;
                    break;
                case "end":
                    Result = d; ResultUntil = Now + ResultSeconds * 1000; Hud = null;
                    Ended();
                    break;
            }
            Changed();
        }

        /// <summary>Own side first: the hud's sides[team] and the other.</summary>
        public List<object> Side(bool mine)
        {
            // the sides are arrays of players: read them straight from the JSON
            var raw = Json.Get(Hud, "sides") as List<object> ?? new List<object>();
            int idx = (mine ? MyTeam : 3 - MyTeam) - 1;
            var list = new List<object>();
            if (idx >= 0 && idx < raw.Count && raw[idx] is List<object> players) foreach (object p in players) if (p is Dictionary<string, object>) list.Add(p);
            return list;
        }

        /// <summary>The queue wait text and the other status line of the window.</summary>
        public string StatusText(double nowMs)
        {
            if (State == null) return Loc.T("Not in a queue.");
            if (InMatch) return Loc.T("You are in a {0} match.", Json.Text(Json.Get(State, "match"), "mode"));
            if (InQueue)
            {
                var q = Json.Get(State, "queue");
                double waited = Json.Number(q, "waited") + (nowMs - StateAt) / 1000.0;
                return Loc.T("In the {0} queue: {1} (rating {2}, window +/-{3})", Json.Text(q, "mode"), Eg.Clock(waited), Json.Int(q, "rating"), Json.Get(q, "window") is double w ? (int)w : 100);
            }
            return Loc.T("Not in a queue.");
        }

        public string RulesLine()
        {
            var rules = Json.Get(State, "rules");
            return Loc.T("Opponent levels {0} - {1}.  First-win bonus: {2}", Json.Int(rules, "levelLow"), Json.Int(rules, "levelHigh"), Json.Truthy(State, "firstWinDone") ? Loc.T("taken") : Loc.T("ready"));
        }

        public string RulesTip()
        {
            var rules = Json.Get(State, "rules");
            return Loc.T("Level {0}+. Countdown {1}s, then {2} to win; on time-out the side with more health (share) wins.",
                Json.Get(rules, "minLevel") is double ml ? (int)ml : 50, Json.Get(rules, "countdown") is double cd ? (int)cd : 10, Eg.Clock(Json.Get(rules, "fight") is double f ? f : 300));
        }

        public void Clear() { State = Hud = Result = null; Visible = false; ResultUntil = -1; MyTeam = 1; }
    }

    // ================================================================================================ Battleground
    public sealed class BgCard { public string Name = "", Rating = "", Record = "", Tier = "", Color = "#d6c9ae", TierKey = "ashen", Decay, Tooltip = ""; public bool Unplaced; }
    public sealed class BgRole { public string Key = "", Text = "", Color = ""; public bool Chosen; }
    public sealed class BgVendor { public string Title = "", Sub = "", Button = ""; public bool Can; }
    public sealed class BgWell { public string Name = "", Text = "", Color = "", Owner = ""; }
    public sealed class BgBoardRow { public string Name = "", Role = "", RoleColor = "", Damage = "", Healing = "", Honor = ""; public int Kills, Assists, Downs, Captures; public bool Left; }
    public sealed class BgSummary { public string Title = "", Color = "", Score = "", Reason = "", Rating = "", Honor = ""; }

    public static class BgView
    {
        public static readonly string[] BracketOrder = { "1v1", "2v2", "3v3", "bg" };

        /// <summary>The headline of the Season tab. No `endsIn` while the launch date is open (O463): "coming soon", not a zero countdown.</summary>
        public static string SeasonTitle(object season, double elapsed)
        {
            int id = Json.Get(season, "id") is double sid ? (int)sid : 1;
            if (!(Json.Get(season, "endsIn") is double endsIn)) return Loc.T("PvP Season {0}: coming soon", id);
            return Loc.T("PvP Season {0}: ends in {1}", id, Eg.SpanLong(endsIn - elapsed));
        }

        public static string RoleName(string r) => r == "tank" ? "Tank" : r == "healer" ? "Healer" : r == "dps" ? "DPS" : r == "support" ? "Support" : "";
        public static string RoleColor(string r) => r == "tank" ? "#7fb8e8" : r == "healer" ? "#6fd8a8" : r == "dps" ? "#e8846a" : r == "support" ? "#c08ae8" : "#d6c9ae";

        public static string Result(string r, out string color)
        {
            color = r == "win" ? "#f6cf72" : r == "loss" ? "#e03a1e" : "#d6c9ae";
            return r == "win" ? "VICTORY" : r == "loss" ? "DEFEAT" : r == "draw" ? "DRAW" : (r ?? "?").ToUpperInvariant();
        }

        public static string Reason(string r)
        {
            switch (r)
            {
                case "score": return "first to the goal"; case "time": return "time ran out"; case "forfeit": return "the other side left"; case "stop": return "stopped by the staff"; default: return r ?? "";
            }
        }

        public static string TierKey(object tiers, double index)
        {
            var list = tiers as List<object>;
            int i = (int)(index <= 0 ? 1 : index);
            return list != null && i >= 1 && i <= list.Count && Json.Get(list[i - 1], "key") is string k ? k : "ashen";
        }

        public static BgCard Card(object view, object tiers, double placementTotal)
        {
            var c = new BgCard
            {
                Name = Json.Get(view, "name") is string n ? n : "?", Rating = (Json.Get(view, "rating") is double r ? (long)r : 1500).ToString(CultureInfo.InvariantCulture),
                Record = Json.Int(view, "wins") + "-" + Json.Int(view, "losses") + "-" + Json.Int(view, "draws"),
            };
            if (Json.Truthy(view, "placed"))
            {
                c.Tier = Json.Text(view, "tierName", "?"); c.Color = Json.Text(view, "color").Length > 0 ? Json.Text(view, "color") : "#d6c9ae"; c.TierKey = TierKey(tiers, Json.Number(view, "tier"));
            }
            else
            {
                double total = placementTotal > 0 ? placementTotal : 5;
                double left = Json.Get(view, "placementLeft") is double pl ? pl : total;
                c.Tier = Loc.T("Placement {0}/{1}", (long)(total - left), (long)total); c.Color = "#8c8070"; c.Rating = "?"; c.Unplaced = true;
            }
            if (Json.Number(view, "decayIn") > 0) c.Decay = Loc.T("Decay in {0} without a rated match", Eg.SpanLong(Json.Number(view, "decayIn")));
            c.Tooltip = Loc.T("Season rating {0} (deviation {1}), peak {2}, {3} matches.", Json.Get(view, "rating") is double rr ? (int)rr : 1500, Json.Int(view, "rd"),
                Json.Get(view, "peak") is double pk ? (int)pk : (Json.Get(view, "rating") is double r2 ? (int)r2 : 1500), Json.Int(view, "matches"));
            return c;
        }

        /// <summary>The queue line and its colour; elapsed is the seconds since the state came.</summary>
        public static string QueueStatus(object state, double elapsed, out string color)
        {
            color = "#d6c9ae";
            if (Json.Get(state, "match") is Dictionary<string, object>) { color = "#f6cf72"; return Loc.T("You are in a battleground match."); }
            double deserter = Json.Number(state, "deserter") - elapsed;
            if (deserter > 0) { color = "#e03a1e"; return Loc.T("Deserter: no queue for {0}.", Eg.SpanLong(deserter)); }
            if (Json.Get(state, "queue") is Dictionary<string, object> q)
            {
                color = "#f6cf72";
                double waited = Json.Number(q, "waited") + elapsed, est = Math.Max(0, Json.Number(q, "est") - elapsed);
                return Loc.T("In the queue {0} ({1} players waiting). Estimated: {2}", Eg.Clock(waited), Json.Int(q, "players"), est > 0 ? "~" + Eg.SpanLong(est) : Loc.T("any moment"));
            }
            if (Json.Get(state, "bracket") == null)
            {
                color = "#e03a1e";
                return Loc.T("You need level {0} for the battleground.", Json.Get(state, "minLevel") is double ml ? (int)ml : 100);
            }
            return Loc.T("{0} waiting in your bracket. Estimated wait: ~{1}", Json.Int(state, "waiting"), Eg.SpanLong(Json.Number(state, "est")));
        }

        public static List<BgRole> RoleOptions(object state)
        {
            var list = new List<BgRole>();
            var roles = Json.Get(state, "roles") as List<object> ?? new List<object> { "dps" };
            string chosen = Json.Text(state, "role");
            foreach (object r in roles) if (r is string k) list.Add(new BgRole { Key = k, Text = RoleName(k).Length > 0 ? RoleName(k) : k, Color = RoleColor(k), Chosen = k == chosen });
            return list;
        }

        public static string HonorLine(object s)
            => Loc.T("Honor {0}   (this week {1} / {2})   Weekly first win: {3}", Eg.Number(Json.Number(s, "honor")), Eg.Number(Json.Number(s, "weekHonor")), Eg.Number(Json.Number(s, "weekCap")),
                Json.Truthy(s, "firstWinDone") ? "taken" : "ready");

        public static string RecordLine(object s)
        {
            var r = Json.Get(s, "record");
            return Loc.T("Battlegrounds {0}   W-L-D {1}-{2}-{3}   Downs dealt {4}   Wells taken {5}", Json.Int(r, "matches"), Json.Int(r, "wins"), Json.Int(r, "losses"), Json.Int(r, "draws"), Json.Int(r, "kills"), Json.Int(r, "captures"));
        }

        public static BgVendor VendorRow(object o, double honor)
        {
            double cost = Json.Number(o, "cost");
            var r = new BgVendor { Title = Json.Text(o, "name", "?"), Button = Eg.Number(cost) + " honor" };
            if (Json.Truthy(o, "owned")) { r.Sub = Loc.T("Unlocked for your account."); r.Button = Loc.T("Owned"); }
            else if (honor < cost) r.Sub = Loc.T("You need {0} more honor.", Eg.Number(cost - honor));
            else { r.Sub = Json.Text(o, "kind") == "cosmetic" ? Loc.T("Cosmetic, account-wide.") : Loc.T("Delivered to your backpack (inbox when full)."); r.Can = true; }
            return r;
        }

        public static double ScorePercent(double score, double goal) { goal = Math.Max(1, goal > 0 ? goal : 1000); return Math.Min(100, Math.Floor(score * 100 / goal)); }

        public static BgWell Brazier(object b, object teams, object colors)
        {
            var tl = teams as List<object> ?? new List<object> { "Team 1", "Team 2" };
            var cl = colors as List<object> ?? new List<object> { "#ff9a3c", "#8fb8ff" };
            Func<List<object>, int, string, string> at = (l, i, f) => i >= 1 && i <= l.Count && l[i - 1] is string s ? s : f;
            double owner = Json.Number(b, "owner"), progress = Json.Number(b, "progress");
            var w = new BgWell { Name = Json.Text(b, "name", "?"), Owner = ((long)owner).ToString(CultureInfo.InvariantCulture) };
            if (Json.Truthy(b, "contested")) { w.Text = "contested"; w.Color = "#ff5050"; }
            else if (owner == 1 || owner == 2)
            {
                w.Text = at(tl, (int)owner, "?"); w.Color = at(cl, (int)owner, "#d6c9ae");
                if ((owner == 1 && progress < 100) || (owner == 2 && progress > -100)) w.Text += " " + (long)Math.Floor(Math.Abs(progress)) + "%";
            }
            else if (progress != 0)
            {
                int t = progress > 0 ? 1 : 2;
                w.Text = (long)Math.Floor(Math.Abs(progress)) + "% " + at(tl, t, "?"); w.Color = at(cl, t, "#d6c9ae");
            }
            else { w.Text = "neutral"; w.Color = "#8c8070"; }
            return w;
        }

        public static string HudCenter(object d, double left, out string small)
        {
            string phase = Json.Text(d, "phase");
            if (phase == "prep") { small = Loc.T("the wells open in"); return ((long)Math.Max(0, Math.Floor(left))).ToString(CultureInfo.InvariantCulture); }
            if (phase == "fight") { small = "left"; return Eg.Clock(left); }
            small = "over";
            return "-";
        }

        public static string HudNotice(object d, double respawn, double afk, out string color)
        {
            if (Json.Get(d, "respawn") != null) { color = "#e03a1e"; return Loc.T("Downed: back with the next wave in {0}s", (long)Math.Max(0, Math.Floor(respawn))); }
            if (Json.Get(d, "afk") != null) { color = "#ff5050"; return Loc.T("Inactive: move or fight within {0}s", (long)Math.Max(0, Math.Floor(afk))); }
            color = "#d6c9ae";
            return "";
        }

        /// <summary>The scoreboard rows split into own team and the other.</summary>
        public static List<BgBoardRow>[] BoardSides(object rows, double myTeam)
        {
            var sides = new[] { new List<BgBoardRow>(), new List<BgBoardRow>() };
            if (!(rows is List<object> list)) return sides;
            if (myTeam <= 0) myTeam = 1;
            foreach (object r in list)
            {
                if (!(r is Dictionary<string, object>)) continue;
                double t = Json.Get(r, "team") is double td ? td : 1;
                bool left = Json.Truthy(r, "left");
                sides[t == myTeam ? 0 : 1].Add(new BgBoardRow
                {
                    Name = Json.Text(r, "name", "?") + (left ? " (left)" : ""), Role = RoleName(Json.Text(r, "role")), RoleColor = RoleColor(Json.Text(r, "role")),
                    Kills = Json.Int(r, "kills"), Assists = Json.Int(r, "assists"), Downs = Json.Int(r, "downs"), Captures = Json.Int(r, "captures"),
                    Damage = Eg.Number(Json.Number(r, "damage")), Healing = Eg.Number(Json.Number(r, "healing")), Honor = Json.Get(r, "honor") is double h ? Eg.Number(h) : "", Left = left,
                });
            }
            return sides;
        }

        public static BgSummary Summary(object d, double myTeam)
        {
            var s = new BgSummary();
            s.Title = Result(Json.Text(d, "result"), out string color); s.Color = color;
            int team = Json.Get(d, "team") is double td ? (int)td : (int)(myTeam > 0 ? myTeam : 1);
            var score = Json.Get(d, "score") as List<object> ?? new List<object> { 0.0, 0.0 };
            var teams = Json.Get(d, "teams") as List<object> ?? new List<object> { "Team 1", "Team 2" };
            Func<List<object>, int, string> name = (l, i) => i >= 1 && i <= l.Count && l[i - 1] is string n ? n : "?";
            Func<int, long> sc = i => i >= 1 && i <= score.Count && score[i - 1] is double v ? (long)v : 0;
            s.Score = name(teams, team) + " " + sc(team) + "  -  " + sc(3 - team) + " " + name(teams, 3 - team);
            s.Reason = Reason(Json.Text(d, "reason"));
            if (Json.Get(d, "rated") != null && !Json.Truthy(d, "rated", true)) { s.Rating = "Not rated"; return s; }
            var se = Json.Get(d, "season");
            if (se is Dictionary<string, object>)
            {
                s.Rating = Loc.T("Season rating {0} -> {1} ({2})", Json.Int(se, "before"), Json.Int(se, "after"), Eg.Delta(Json.Number(se, "delta")));
                s.Rating += Json.Truthy(se, "placed") ? "  " + Json.Text(se, "tierName") : Loc.T("  (placement: {0} left)", Json.Int(se, "placementLeft"));
            }
            s.Honor = Loc.T("Honor +{0}{1}", Json.Int(d, "honor"), Json.Truthy(d, "firstWin") ? Loc.T(" (first win of the week)") : "");
            if (Json.Text(d, "items").Length > 0) s.Honor += "  " + Json.Text(d, "items");
            return s;
        }
    }

    public sealed class BattlegroundState : EgModule
    {
        public const byte Opcode = 200;
        protected override byte Op => Opcode;

        public object State, Hud, Board, Summary;
        public double StateAt, HudAt;
        public string Tab = "queue", Message = "";
        public bool MessageOk, Visible, BoardVisible;
        public int MyTeam = 1;
        public Action Started = delegate { }, Ended = delegate { };
        /// <summary>The server's alert lines (a well taken, a wave): the app shows them as game messages.</summary>
        public Action<string> Alert = delegate { };

        public BattlegroundState(ExtOpcodes e) : base(e) { ext.On(Opcode, m => Handle(m.Action, Eg.DataOf(m))); }

        public bool InMatch => State != null && Json.Get(State, "match") is Dictionary<string, object>;
        public bool InQueue => State != null && Json.Get(State, "queue") is Dictionary<string, object>;

        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void Show() { Visible = true; Message = ""; Send("open"); Changed(); }
        public void Hide() { Visible = false; }
        public void ShowTab(string tab) { Tab = tab; Changed(); }
        public void SetRole(string role) { Send("role", D("role", role)); }
        public void Buy(string key) { Send("buy", D("key", key)); }

        /// <summary>Queue as the chosen role, leave the queue, or (in a match) leave it: the caller asks first for the match.</summary>
        public void QueueOrLeave()
        {
            if (State == null) return;
            if (InMatch || InQueue) Send("leave");
            else Send("queue", D("role", Json.Text(State, "role")));
        }

        public bool CanQueue => State != null && Json.Get(State, "bracket") != null && Json.Number(State, "deserter") <= 0;

        public void ToggleBoard()
        {
            if (BoardVisible) { BoardVisible = false; return; }
            Summary = null;
            Send("board");
            BoardVisible = true;
            Changed();
        }

        public void HideBoard() { BoardVisible = false; }

        public void Handle(string action, object d)
        {
            switch (action)
            {
                case "state":
                    State = d; StateAt = Now;
                    if (Json.Truthy(d, "open")) { Message = ""; Visible = true; }
                    break;
                case "start":
                    MyTeam = Json.Get(d, "team") is double t ? (int)t : 1;
                    Summary = null; Visible = false; BoardVisible = false;
                    Started();
                    break;
                case "hud": Hud = d; HudAt = Now; if (Json.Get(d, "team") is double tm) MyTeam = (int)tm; break;
                case "board": Board = d; break;
                case "alert": if (Json.Text(d, "text").Length > 0) Alert(Json.Text(d, "text")); break;
                case "end":
                    Summary = d; BoardVisible = true; Hud = null;
                    Ended();
                    break;
                case "msg":
                    if (Visible) { Message = Json.Text(d, "text"); MessageOk = Json.Truthy(d, "ok"); }
                    else if (Json.Text(d, "text").Length > 0) Notice(Json.Text(d, "text"));
                    break;
            }
            Changed();
        }

        /// <summary>The scoreboard data (the match summary when it ended, else the live board).</summary>
        public object BoardData => Summary ?? Board;
        public double Elapsed(double nowMs) => Math.Max(0, (nowMs - StateAt) / 1000.0);
        public double HudElapsed(double nowMs) => Math.Max(0, (nowMs - HudAt) / 1000.0);

        public void Clear() { State = Hud = Board = Summary = null; Visible = BoardVisible = false; Tab = "queue"; Message = ""; MyTeam = 1; }
    }

    // ================================================================================================ Scorched Marches
    public sealed class PzMark { public string Kind = "", Name = ""; public int X, Y, Z; }

    public static class PvpZoneView
    {
        public static string EmbersLine(object d) => Loc.T("Embers {0} / {1}", Eg.Number(Json.Number(d, "embers")), Eg.Number(Json.Number(d, "cap")));

        public static double CarryPercent(object d, out string color)
        {
            double cap = Json.Number(d, "cap");
            color = "#e8a040";
            if (cap <= 0) return 0;
            double p = Math.Min(100, Math.Floor(Json.Number(d, "embers") * 100 / cap));
            if (p >= 90) color = "#ff5a2a";
            return p;
        }

        public static string ContestLine(object c, double left, out string color)
        {
            string phase = Json.Text(c, "phase");
            if (phase == "warden")
            {
                color = "#ff7040";
                return Loc.T("Shrine Warden {0}- {1} left", Json.Get(c, "warden") is double w ? (long)w + "% " : "", Eg.Clock(left));
            }
            if (phase == "capture")
            {
                if (Json.Truthy(c, "contested")) { color = "#ff4030"; return Loc.T("Shrine: CONTESTED - {0} left", Eg.Clock(left)); }
                var prog = Json.List(c, "progress");
                if (prog.Count > 0)
                {
                    var lead = prog[0];
                    color = Json.Text(lead, "color").Length > 0 ? Json.Text(lead, "color") : "#f6cf72";
                    return Loc.T("Shrine: {0} {1}% - {2} left", Json.Get(lead, "short") is string sh ? sh : Json.Text(lead, "name"), Json.Int(lead, "pct"), Eg.Clock(left));
                }
                color = "#f6cf72";
                return Loc.T("Shrine: open, take it! - {0} left", Eg.Clock(left));
            }
            color = "#b8ab92";
            return Loc.T("Shrine contest in {0}", Eg.Clock(left));
        }

        public static string HolderLine(object c, out string color)
        {
            var h = Json.Get(c, "holder");
            if (!(h is Dictionary<string, object>)) { color = "#8c8070"; return Loc.T("Nobody holds the Cinder Shrine"); }
            color = Json.Text(h, "color").Length > 0 ? Json.Text(h, "color") : "#f6cf72";
            return Loc.T("{0} hold the shrine ({1})", Json.Get(h, "short") is string sh ? sh : Json.Text(h, "name"), Eg.SpanHours(Json.Number(h, "left")));
        }

        public static string PledgeLine(object p, out string color)
        {
            if (!(p is Dictionary<string, object>)) { color = "#8c8070"; return Loc.T("Not pledged: no reputation, no shrine"); }
            color = Json.Text(p, "color").Length > 0 ? Json.Text(p, "color") : "#d6c9ae";
            return Loc.T("Fighting for {0}", Json.Get(p, "name") is string n ? n : Json.Text(p, "key"));
        }

        public static string StatusLine(object d, double protect, out string color)
        {
            if (Json.Get(d, "exit") is double ex) { color = "#9fd89f"; return Loc.T("Leaving... {0}% (do not fight)", (long)ex); }
            if (protect > 0) { color = "#8fb8ff"; return Loc.T("Protected for {0}s", (long)Math.Floor(protect)); }
            if (Json.Number(d, "piles") > 0) { color = "#e8a040"; return Loc.T("{0} embers lie on the ground", Eg.Number(Json.Number(d, "piles"))); }
            color = "#8c8070";
            return Loc.T("Bank your embers at a safe exit");
        }

        /// <summary>The Enter button: text, enabled and the tip.</summary>
        public static string EnterButton(object s, out bool enabled, out string tip)
        {
            if (Json.Truthy(s, "inside")) { enabled = false; tip = Loc.T("Leave through a safe exit to bank your embers."); return "Inside"; }
            if (!Json.Truthy(s, "canEnter")) { enabled = false; tip = Json.Text(s, "why"); return "Enter"; }
            enabled = true; tip = Loc.T("Opens the rules and the confirmation first.");
            return Loc.T("Enter the Marches");
        }

        public static bool CanConfirm(object s, bool accepted, bool hcAccepted)
        {
            if (!accepted) return false;
            var hc = Json.Get(s, "hc");
            if (Json.Truthy(hc, "isHc")) return Json.Truthy(hc, "allow") && hcAccepted;
            return true;
        }

        public static string RiskText(object s)
        {
            var lines = new List<string>();
            foreach (string r in Eg.Strings(s, "rules")) lines.Add("- " + r);
            lines.Add(Loc.T("You carry {0} embers now. A defeat drops them all; your killer may take up to {1} of them.", Eg.Number(Json.Number(s, "carried")), Eg.Number(Json.Number(Json.Get(s, "pickup"), "perKill"))));
            var hc = Json.Get(s, "hc");
            if (Json.Truthy(hc, "isHc")) lines.Add(Json.Truthy(hc, "allow") ? Loc.T("HARDCORE: a defeat here may end your Hardcore run.") : Loc.T("HARDCORE: Hardcore characters cannot enter the Marches."));
            return string.Join("\n", lines);
        }

        public static string FactionRow(object f, object s, out string button, out bool enabled, out string tip)
        {
            string name = Json.Text(f, "name");
            string rivalName = Json.Get(f, "rivalName") as string ?? Json.Get(f, "rival") as string;
            string rival = rivalName != null ? Loc.T("sworn rival: {0}", rivalName) : "";
            if (Json.Truthy(f, "pledged"))
            {
                double wait = Json.Number(s, "pledgeChangeIn");
                button = "Pledged"; enabled = false; tip = wait > 0 ? Loc.T("You can change in {0}", Eg.SpanHours(wait)) : rival;
                return name;
            }
            button = "Pledge"; enabled = Json.Truthy(f, "can"); tip = Json.Get(f, "why") is string why ? why : rival;
            return name;
        }

        public static string VendorRow(object o, double banked, out string button, out bool enabled)
        {
            string sub;
            if (Json.Get(o, "weekly") is double w) sub = Loc.T("{0} of {1} this week", Json.Int(o, "bought"), (long)w);
            else if (Json.Text(o, "kind") == "cosmetic") sub = "Cosmetic, account-wide";
            else sub = "Consumable";
            if (Json.Truthy(o, "owned")) { button = "Owned"; enabled = false; return sub; }
            button = Eg.Number(Json.Number(o, "cost")) + " embers";
            enabled = Json.Truthy(o, "can") && banked >= Json.Number(o, "cost");
            return sub;
        }

        public static string RecordLine(object s)
            => Loc.T("Banked {0} (this week {1}, all time {2})   Defeats dealt {3}, taken {4}   Shrines {5}", Eg.Number(Json.Number(s, "banked")), Eg.Number(Json.Number(s, "weekBanked")),
                Eg.Number(Json.Number(s, "total")), Eg.Number(Json.Number(s, "kills")), Eg.Number(Json.Number(s, "defeats")), Eg.Number(Json.Number(s, "captures")));

        public static List<string> Steps(object s)
        {
            var list = new List<string>
            {
                Loc.T("Pledge to a faction in this window, outside the zone. Pledged players earn reputation and can take the shrine."),
                Loc.T("Enter from a protection zone. Kill monsters and rival players: every kill gives embers, which you carry (at most {0}).", Eg.Number(Json.Get(s, "carryMax") is double cm ? cm : 2500)),
                Loc.T("Carried embers are at risk. If you are defeated you drop them all and your killer may take up to {0}. Equipment and experience are never lost.", Eg.Number(Json.Get(Json.Get(s, "pickup"), "perKill") is double pk ? pk : 800)),
                Loc.T("Bank them: stand {0}s in a white safe-exit circle without fighting (the circles are marked on your map). Banked embers are safe and buy orbs, potions and cosmetics from the vendor below.", Json.Get(s, "exitSeconds") is double es ? (long)es : 5),
            };
            for (int i = 0; i < list.Count; i++) list[i] = (i + 1) + ". " + list[i];
            return list;
        }

        /// <summary>Marks of a safe exit or the shrine (at most 8, whole coordinates).</summary>
        public static List<PzMark> CleanMarks(object list)
        {
            var o = new List<PzMark>();
            if (!(list is List<object> l)) return o;
            foreach (object m in l)
            {
                string kind = Json.Text(m, "kind");
                if (!(m is Dictionary<string, object>) || (kind != "exit" && kind != "shrine")) continue;
                if (!(Json.Get(m, "x") is double x) || !(Json.Get(m, "y") is double y) || !(Json.Get(m, "z") is double z) || o.Count >= 8) continue;
                o.Add(new PzMark { Kind = kind, X = (int)Math.Floor(x), Y = (int)Math.Floor(y), Z = (int)Math.Floor(z), Name = Json.Text(m, "name") });
            }
            return o;
        }

        /// <summary>Distance in tiles and the compass word (n, ne, e, se, s, sw, w, nw) from a point to a mark; null at the same tile.</summary>
        public static int Compass(int fx, int fy, int tx, int ty, out string dir)
        {
            int dx = tx - fx, dy = ty - fy, ax = Math.Abs(dx), ay = Math.Abs(dy), dist = Math.Max(ax, ay);
            dir = null;
            if (dist == 0) return 0;
            string ns = dy < 0 ? "n" : "s", ew = dx > 0 ? "e" : "w";
            if (ay * 2 <= ax) dir = ew;
            else if (ax * 2 <= ay) dir = ns;
            else dir = ns + ew;
            return dist;
        }

        public static string WhereText(int dist, string dir)
        {
            if (dir == null) return Loc.T("you are here");
            switch (dir)
            {
                case "n": return Loc.T("{0} tiles north", dist); case "ne": return Loc.T("{0} tiles north-east", dist); case "e": return Loc.T("{0} tiles east", dist);
                case "se": return Loc.T("{0} tiles south-east", dist); case "s": return Loc.T("{0} tiles south", dist); case "sw": return Loc.T("{0} tiles south-west", dist);
                case "w": return Loc.T("{0} tiles west", dist); default: return Loc.T("{0} tiles north-west", dist);
            }
        }

        /// <summary>The nearest mark of a kind on the player's floor and where it lies, null when none.</summary>
        public static PzMark Nearest(IList<PzMark> marks, string kind, int px, int py, int pz, out string where)
        {
            PzMark best = null; int bd = 0; string bdir = null; where = null;
            foreach (var m in marks)
            {
                if (m.Kind != kind || m.Z != pz) continue;
                int d = Compass(px, py, m.X, m.Y, out string dir);
                if (best == null || d < bd) { best = m; bd = d; bdir = dir; }
            }
            if (best != null) where = WhereText(bd, bdir);
            return best;
        }

        public static List<KeyValuePair<string, string>> GoalLines(object d, string exitWhere, string shrineWhere)
        {
            var lines = new List<KeyValuePair<string, string>>();
            Action<string, string> add = (t, c) => lines.Add(new KeyValuePair<string, string>(t, c));
            double carried = Json.Number(d, "embers");
            if (Json.Get(d, "exit") is double)
            {
                add(Loc.T("Leaving... hold still, do not fight. Your {0} embers are banked when the bar is full.", Eg.Number(carried)), "#9fd89f");
                return lines;
            }
            if (carried > 0)
            {
                if (exitWhere != null) add(Loc.T("Embers carried: {0}. Bank them at the nearest safe exit ({1}, marked on your map) before you are defeated.", Eg.Number(carried), exitWhere), "#f6cf72");
                else add(Loc.T("Embers carried: {0}. Bank them at a safe exit (marked on your map) before you are defeated.", Eg.Number(carried)), "#f6cf72");
            }
            else add(Loc.T("Goal: kill monsters and rival players for embers, then bank them at a safe exit (marked on your map)."), "#b8ab92");
            var c = Json.Get(d, "contest");
            string phase = Json.Text(c, "phase");
            bool pledged = Json.Get(d, "pledge") is Dictionary<string, object>;
            if (phase == "warden")
                add(shrineWhere != null ? Loc.T("Shrine event: slay the Shrine Warden at the shrine ({0}, marked on your map).", shrineWhere) : Loc.T("Shrine event: slay the Shrine Warden at the shrine (marked on your map)."), "#ff7040");
            else if (phase == "capture")
            {
                if (pledged) add(shrineWhere != null ? Loc.T("Shrine event: stand in the shrine circle with your faction to take it ({0}, marked on your map).", shrineWhere) : Loc.T("Shrine event: stand in the shrine circle with your faction to take it (marked on your map)."), "#ff7040");
                else add(Loc.T("Shrine event: only players pledged to a faction can take the shrine."), "#8c8070");
            }
            return lines;
        }
    }

    public sealed class PvpZoneState : EgModule
    {
        public const byte Opcode = 193;
        protected override byte Op => Opcode;

        public object State, Hud;
        public double HudAt;
        public bool Visible, ConfirmAsked;
        public string Message = "";
        public bool MessageOk;
        public List<PzMark> Marks = new List<PzMark>();
        public Action Started = delegate { }, Ended = delegate { };

        public PvpZoneState(ExtOpcodes e) : base(e) { ext.On(Opcode, m => Handle(m.Action, Eg.DataOf(m))); }

        public void Query() { Send("query"); }
        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void Show() { Visible = true; Message = ""; Send("open"); Changed(); }
        public void Hide() { Visible = false; }
        public bool Pledge(string faction) { return Send("pledge", D("faction", faction)); }
        public bool Buy(string key) { return Send("buy", D("key", key)); }

        /// <summary>Confirms entering (the box was ticked); false when the rules do not allow it yet.</summary>
        public bool Enter(bool accepted, bool hcAccepted)
        {
            if (!PvpZoneView.CanConfirm(State, accepted, hcAccepted)) return false;
            var d = D("accept", true);
            if (hcAccepted) d["hcAccept"] = true;
            ConfirmAsked = false;
            return Send("enter", d);
        }

        public void CancelConfirm() { ConfirmAsked = false; }

        public bool Inside => Hud != null;

        public void Handle(string action, object d)
        {
            switch (action)
            {
                case "state":
                    State = d;
                    if (Json.Truthy(d, "open") || Json.Truthy(d, "confirm")) Visible = true;
                    if (Json.Truthy(d, "confirm")) ConfirmAsked = true;
                    break;
                case "hud": Hud = d; HudAt = Now; break;
                case "enter": Visible = false; ConfirmAsked = false; Marks = PvpZoneView.CleanMarks(Json.Get(d, "marks")); Started(); break;
                case "hide": Hud = null; Marks = new List<PzMark>(); ConfirmAsked = false; Ended(); break;
                case "msg":
                    if (Visible) { Message = Json.Text(d, "text"); MessageOk = Json.Truthy(d, "ok"); }
                    else if (Json.Text(d, "text").Length > 0) Notice(Json.Text(d, "text"));
                    break;
            }
            Changed();
        }

        public double HudElapsed(double nowMs) => Math.Max(0, Math.Floor((nowMs - HudAt) / 1000.0));

        public void Clear() { State = Hud = null; Visible = ConfirmAsked = false; Marks = new List<PzMark>(); Message = ""; }
    }

    // ================================================================================================ Bounty board
    public sealed class BountyContract
    {
        public string Key = "", Type = "", Name = "", Tier = "", State = "open";
        public int Count = 1, Progress, Level;
        public object Outfit, Reward;
        public double Look;
    }

    public sealed class BountyBand { public int Index; public bool HasIndex; public string Label = ""; public bool Own; public List<BountyContract> Contracts = new List<BountyContract>(); }

    public static class BountyView
    {
        public static string KindText(string t) => t == "hunt" ? "HUNT" : t == "elite" ? "ELITE" : t == "boss" ? "BOSS" : Capitalize(t);
        public static string KindColor(string t) => t == "elite" ? "#b070ff" : t == "boss" ? "#e03a1e" : "#8c8070";
        public static string TierColor(string t) => t == "magic" ? "#5a8fff" : t == "rare" ? "#f6cf72" : t == "legendary" ? "#e8582a" : null;

        public static string Capitalize(string s) => string.IsNullOrEmpty(s) ? "" : char.ToUpperInvariant(s[0]) + s.Substring(1);

        public static string Plural(string name, int count)
        {
            if (count == 1) return name;
            string lower = name.ToLowerInvariant();
            if (lower.EndsWith("s", StringComparison.Ordinal)) return name;
            if (lower.Length >= 2 && lower.EndsWith("y", StringComparison.Ordinal) && "aeiou".IndexOf(lower[lower.Length - 2]) < 0) return name.Substring(0, name.Length - 1) + "ies";
            if (lower.EndsWith("x", StringComparison.Ordinal) || lower.EndsWith("ch", StringComparison.Ordinal) || lower.EndsWith("sh", StringComparison.Ordinal)) return name + "es";
            if (lower.EndsWith("man", StringComparison.Ordinal)) return name.Substring(0, name.Length - 3) + "men";
            return name + "s";
        }

        public static string TaskText(BountyContract c)
        {
            if (c.Type == "boss") return c.Count > 1 ? Loc.T("Slay the boss {0} times.", c.Count) : Loc.T("Slay the boss once.");
            if (c.Type == "elite") return Loc.T("Kill {0} {1} or stronger {2}.", c.Count, c.Tier.Length > 0 ? c.Tier : "magic", Plural(c.Name, c.Count));
            return Loc.T("Kill {0} {1}.", c.Count, Plural(c.Name, c.Count));
        }

        /// <summary>The short reward line and the exact one (the tooltip).</summary>
        public static string RewardText(object r, out string exact)
        {
            var parts = new List<string>(); var ex = new List<string>();
            double gold = Json.Number(r, "gold"), chaos = Json.Number(r, "chaos"), divine = Json.Number(r, "divine"), exp = Json.Number(r, "exp");
            if (gold > 0) { parts.Add(Fmt.Short(gold) + " gold"); ex.Add(Loc.T("{0} gold to your bank", Eg.Number(gold))); }
            if (chaos > 0) { string t = (long)chaos + (chaos > 1 ? Loc.T(" Orbs of Upheaval") : Loc.T(" Orb of Upheaval")); parts.Add(t); ex.Add(t); }
            if (divine > 0) { string t = (long)divine + (divine > 1 ? Loc.T(" Orbs of Fate") : Loc.T(" Orb of Fate")); parts.Add(t); ex.Add(t); }
            if (exp > 0) { parts.Add(Fmt.Short(exp) + " exp"); ex.Add(Eg.Number(exp) + " experience"); }
            exact = Loc.T("Reward:") + "\n" + string.Join("\n", ex);
            return string.Join(", ", parts);
        }

        /// <summary>"1h 05m 09s" as the board's formatTime.</summary>
        public static string FormatTime(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            return (s / 3600) + "h " + (s % 3600 / 60).ToString("00", CultureInfo.InvariantCulture) + "m " + (s % 60).ToString("00", CultureInfo.InvariantCulture) + "s";
        }
    }

    public sealed class BountyState : EgModule
    {
        public const byte Opcode = 223;
        protected override byte Op => Opcode;

        public bool Visible, HasBoard;
        public double BoardAt, NextIn;
        public int Day, Band, Active, MaxActive = 3, Rerolls, WeekDone, WeekNeed = 7;
        public bool WeekClaimed;
        public List<BountyBand> Bands = new List<BountyBand>();
        public int SelectedBand;
        public bool SelectedHasBand;
        bool refreshAsked;

        public BountyState(ExtOpcodes e) : base(e) { ext.On(Opcode, m => Handle(m.Action, Eg.DataOf(m))); }

        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void Show() { Visible = true; Send("open"); Changed(); }
        public void Hide() { Visible = false; }
        public bool Accept(string key) { return Send("accept", D("key", key)); }
        public bool Abandon(string key) { return Send("abandon", D("key", key)); }
        public bool Reroll(string key) { return Send("reroll", D("key", key)); }

        public void Handle(string action, object d)
        {
            if (action == "board") OnBoard(d);
            else if (action == "progress") OnProgress(d);
            Changed();
        }

        void OnBoard(object d)
        {
            HasBoard = true; BoardAt = Now; refreshAsked = false;
            Day = Json.Int(d, "day"); NextIn = Json.Number(d, "nextIn"); Band = Json.Int(d, "band"); Active = Json.Int(d, "active");
            MaxActive = Json.Get(d, "maxActive") is double ma ? (int)ma : 3; Rerolls = Json.Int(d, "rerolls");
            var w = Json.Get(d, "week");
            WeekDone = Json.Int(w, "done"); WeekNeed = Json.Get(w, "need") is double wn ? (int)wn : 7; WeekClaimed = Json.Truthy(w, "claimed");
            Bands = new List<BountyBand>();
            foreach (object b in Eg.Objects(d, "bands"))
            {
                var band = new BountyBand { HasIndex = Json.Get(b, "index") is double, Index = Json.Int(b, "index"), Label = Json.Text(b, "label"), Own = Json.Truthy(b, "own") };
                foreach (object c in Eg.Objects(b, "contracts"))
                    band.Contracts.Add(new BountyContract
                    {
                        Key = Json.Text(c, "key"), Type = Json.Text(c, "type"), Name = Json.Text(c, "name", "?"), Tier = Json.Text(c, "tier"), State = Json.Get(c, "state") as string ?? "open",
                        Count = Json.Get(c, "count") is double cn ? (int)cn : 1, Progress = Json.Int(c, "progress"), Level = Json.Int(c, "level"), Outfit = Json.Get(c, "outfit"),
                        Reward = Json.Get(c, "reward"), Look = Json.Number(c, "look"),
                    });
                Bands.Add(band);
            }
            // keep the tab, else the band of the character's level, else the first
            if (!SelectedHasBand || !Bands.Exists(b => b.HasIndex && b.Index == SelectedBand))
            {
                var own = Bands.Find(b => b.HasIndex && b.Index == Band) ?? (Bands.Count > 0 ? Bands[0] : null);
                SelectedHasBand = own != null && own.HasIndex;
                SelectedBand = own != null ? own.Index : 0;
            }
            if (Json.Truthy(d, "open")) Visible = true;
        }

        void OnProgress(object d)
        {
            if (!HasBoard) return;
            foreach (var b in Bands)
                foreach (var c in b.Contracts)
                    if (c.Key == Json.Text(d, "key"))
                    {
                        if (Json.Get(d, "progress") is double p) c.Progress = (int)p;
                        if (Json.Get(d, "state") is string s) c.State = s;
                    }
        }

        public BountyBand Current => Bands.Find(b => b.HasIndex == SelectedHasBand && (!b.HasIndex || b.Index == SelectedBand));
        public void SelectBand(BountyBand band) { SelectedHasBand = band.HasIndex; SelectedBand = band.Index; Changed(); }
        public bool Full => Active >= MaxActive;

        /// <summary>Seconds to the next contracts; at 0 the window asks again once (after 3 s), as the main client does.</summary>
        public double NextLeft(double nowMs) => NextIn - (nowMs - BoardAt) / 1000.0;

        public bool WantsRefresh(double nowMs)
        {
            if (!Visible || !HasBoard || refreshAsked || NextLeft(nowMs) > -3) return false;
            refreshAsked = true;
            return true;
        }

        public void Refresh() { Send("open"); }
        public string ActiveText() => Loc.T("Active contracts: {0} / {1}", Active, MaxActive);
        public string WeekText() => WeekClaimed ? Loc.T("Weekly chest: collected") : Loc.T("Weekly chest: {0} / {1}", Math.Min(WeekDone, WeekNeed), WeekNeed);

        public void Clear() { Visible = HasBoard = false; Bands = new List<BountyBand>(); SelectedHasBand = false; Active = 0; }
    }
}
