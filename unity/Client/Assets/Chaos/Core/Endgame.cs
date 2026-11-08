// Endgame activities (O433 phase 4, track L): the models of the Infinity Tower (214), Dungeons (109), the Ashen Sepulchre raid (213), the Ember
// Descent (205), the Rift and Waystone atlases (210, 159), invasions (251), the guild siege (233), the arena (236), the battleground (200),
// the Scorched Marches (193) and the bounty board (223). This file holds the shared parts: number and time text, the module base, the
// call-out line and the Endgame object a GameSession owns. The modules: EndgamePve.cs, EndgameAtlas.cs, EndgamePvp.cs. Texts: LocEndgame.cs.
//
// Every module keeps the main client's rules (its *view.lua / *math.lua) and the same request actions. Time: the session clock is in
// milliseconds, the servers send seconds; "sent" values are seconds counted from the moment the message came (Left).
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    /// <summary>An item row of a reward list: client id, count and name.</summary>
    public sealed class EgItem
    {
        public int Id, Count;
        public string Name = "";

        public static List<EgItem> ListOf(object data, string key)
        {
            var list = new List<EgItem>();
            foreach (object o in Json.List(data, key))
                if (o is Dictionary<string, object>) list.Add(new EgItem { Id = Json.Int(o, "id"), Count = Json.Int(o, "count"), Name = Json.Text(o, "name") });
            return list;
        }

        /// <summary>"30 Gold Coin, 1 Prize" (the tower's reward text).</summary>
        public static string Text(IList<EgItem> items)
        {
            var parts = new List<string>();
            foreach (var it in items) parts.Add(it.Count.ToString(CultureInfo.InvariantCulture) + " " + (it.Name.Length > 0 ? it.Name : "?"));
            return string.Join(", ", parts);
        }
    }

    /// <summary>Text helpers the activities share (the main client's clock, number, span and countdown functions).</summary>
    public static class Eg
    {
        public static string Clock(double seconds) => Fmt.Clock(seconds);

        /// <summary>1234567 -> "1,234,567", keeps the sign.</summary>
        public static string Number(double n)
        {
            long v = (long)Math.Floor(double.IsNaN(n) ? 0 : n);
            return v.ToString("N0", CultureInfo.InvariantCulture);
        }

        /// <summary>Seconds left of a value the server sent receivedAtMs ago, never below 0.</summary>
        public static double Left(double sentSeconds, double receivedAtMs, double nowMs)
            => Math.Max(0, Math.Floor(sentSeconds - Math.Max(0, (nowMs - receivedAtMs) / 1000.0)));

        /// <summary>Raid reset text: "2d 3h", "3h 12m", "12m".</summary>
        public static string ResetText(double secs)
        {
            long s = (long)Math.Max(0, Math.Floor(secs));
            long d = s / 86400, h = s / 3600 % 24, m = s / 60 % 60;
            if (d > 0) return d + "d " + h + "h";
            if (h > 0) return h + "h " + m + "m";
            return m + "m";
        }

        /// <summary>Dungeons span: "1d 2h", "3h 05m", "12m".</summary>
        public static string Span(double secs)
        {
            long s = (long)Math.Max(0, Math.Floor(secs));
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60;
            if (d > 0) return d + "d " + h + "h";
            if (h > 0) return h + "h " + m.ToString("00", CultureInfo.InvariantCulture) + "m";
            return m + "m";
        }

        /// <summary>Battleground span: "40s", "12m", "3h 5m", "2d 3h", "1w 2d".</summary>
        public static string SpanLong(double secs)
        {
            long s = (long)Math.Max(0, Math.Floor(secs));
            if (s < 60) return s + "s";
            if (s < 3600) return s / 60 + "m";
            if (s < 86400) return s / 3600 + "h " + s % 3600 / 60 + "m";
            if (s < 7 * 86400) return s / 86400 + "d " + s % 86400 / 3600 + "h";
            return s / 604800 + "w " + s % 604800 / 86400 + "d";
        }

        /// <summary>The Marches' span: "40s", "12m", "3h 5m", "2h".</summary>
        public static string SpanHours(double secs)
        {
            long s = (long)Math.Max(0, Math.Floor(secs));
            if (s < 60) return s + "s";
            if (s < 3600) return s / 60 + "m";
            long h = s / 3600, m = s % 3600 / 60;
            return m > 0 ? h + "h " + m + "m" : h + "h";
        }

        /// <summary>"+12" or "-3".</summary>
        public static string Delta(double d)
        {
            long v = (long)Math.Floor(double.IsNaN(d) ? 0 : d);
            return (v >= 0 ? "+" : "") + v.ToString(CultureInfo.InvariantCulture);
        }

        /// <summary>The queue colour of the dungeon list: 6+ red, 3+ orange, else green.</summary>
        public static string QueueColor(int players) => players >= 6 ? "#e03a1e" : players >= 3 ? "#f6a030" : "#7fd07f";

        /// <summary>A "#rrggbb" colour as it came, else the fallback (a server colour is never trusted blindly).</summary>
        public static string Hex(string color, string fallback)
        {
            if (color == null || color.Length != 7 || color[0] != '#') return fallback;
            for (int i = 1; i < 7; i++) if (!Uri.IsHexDigit(color[i])) return fallback;
            return color;
        }

        /// <summary>3725 -> "1:02 h".</summary>
        public static string HoursMinutes(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            return (s / 3600).ToString(CultureInfo.InvariantCulture) + ":" + (s % 3600 / 60).ToString("00", CultureInfo.InvariantCulture) + " h";
        }

        /// <summary>"d days, hh:mm:ss" or "hh:mm:ss" (the tower's season timers); "Now" at 0.</summary>
        public static string TimeRemaining(double seconds)
        {
            long s = (long)Math.Floor(seconds);
            if (s <= 0) return "Now";
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60, sec = s % 60;
            string hms = h.ToString("00", CultureInfo.InvariantCulture) + ":" + m.ToString("00", CultureInfo.InvariantCulture) + ":" + sec.ToString("00", CultureInfo.InvariantCulture);
            return d > 0 ? Loc.T("{0} days, {1}", d, hms) : hms;
        }

        /// <summary>A list of strings of a JSON array (non-strings dropped).</summary>
        public static List<string> Strings(object data, string key)
        {
            var list = new List<string>();
            foreach (object o in Json.List(data, key)) if (o is string s) list.Add(s);
            return list;
        }

        /// <summary>The objects of a JSON array (entries that are no object are left out, as the main client's list helpers do).</summary>
        public static List<object> Objects(object data, string key)
        {
            var list = new List<object>();
            foreach (object o in Json.List(data, key)) if (o is Dictionary<string, object>) list.Add(o);
            return list;
        }

        /// <summary>The "data" of a message as an object (an empty one when it is missing, as the main client's `msg.data or {}`).</summary>
        public static object DataOf(ExtMessage m) => m.Data is Dictionary<string, object> ? m.Data : new Dictionary<string, object>();
    }

    /// <summary>A module on an extended opcode: the connection, the session clock (ms), a change callback and the {action, data} send.</summary>
    public abstract class EgModule
    {
        protected readonly ExtOpcodes ext;
        public Func<double> Clock = () => 0;
        public Action Changed = delegate { };
        /// <summary>A line for the player's text log (a refusal the server sent as msg).</summary>
        public Action<string> Notice = delegate { };
        protected abstract byte Op { get; }

        protected EgModule(ExtOpcodes e) { ext = e; }

        protected bool Send(string action, Dictionary<string, object> data = null)
            => ext.Send(Op, action, data ?? new Dictionary<string, object>());

        protected static Dictionary<string, object> D(params object[] kv)
        {
            var d = new Dictionary<string, object>();
            for (int i = 0; i + 1 < kv.Length; i += 2) d[(string)kv[i]] = kv[i + 1];
            return d;
        }

        protected double Now => Clock();
    }

    /// <summary>A short line over the map with a colour kind and an expiry (the raid call-out).</summary>
    public sealed class EgCallout
    {
        public string Text = "", Kind = "";
        public double Until = -1;
        public bool Active(double nowMs) => Text.Length > 0 && nowMs < Until;
        public void Show(string text, string kind, double nowMs, double seconds) { Text = text ?? ""; Kind = kind ?? ""; Until = nowMs + seconds * 1000; }
        public void Clear() { Text = ""; Kind = ""; Until = -1; }
    }

    /// <summary>The endgame modules of one session (GameSession.Endgame).</summary>
    public sealed class Endgame
    {
        public readonly TowerState Tower;
        public readonly DungeonsState Dungeons;
        public readonly RaidState Raid;
        public readonly DescentState Descent;
        public readonly AtlasState RiftAtlas, WaystoneAtlas;
        public readonly InvasionState Invasion;
        public readonly SiegeState Siege;
        public readonly ArenaState Arena;
        public readonly BattlegroundState Battleground;
        public readonly PvpZoneState PvpZone;
        public readonly BountyState Bounty;
        bool started;

        public Endgame(ExtOpcodes e, Func<double> clock, Func<double> unixNow)
        {
            Tower = new TowerState(e) { Clock = clock, UnixNow = unixNow };
            Dungeons = new DungeonsState(e) { Clock = clock };
            Raid = new RaidState(e) { Clock = clock };
            Descent = new DescentState(e) { Clock = clock };
            RiftAtlas = new AtlasState(e, AtlasState.RiftOpcode) { Clock = clock };
            WaystoneAtlas = new AtlasState(e, AtlasState.WaystoneOpcode) { Clock = clock };
            Invasion = new InvasionState(e) { Clock = clock };
            Siege = new SiegeState(e) { Clock = clock };
            Arena = new ArenaState(e) { Clock = clock };
            Battleground = new BattlegroundState(e) { Clock = clock };
            PvpZone = new PvpZoneState(e) { Clock = clock };
            Bounty = new BountyState(e) { Clock = clock };
        }

        /// <summary>The first requests, a moment after the login (each main module asks on game start).</summary>
        public void Start()
        {
            if (started) return;
            started = true;
            Tower.QueryState();
            Dungeons.Fetch();
            Raid.Query();
            Descent.Query();
            Invasion.Query();
            PvpZone.Query();
        }

        /// <summary>A new character must not see this one's state.</summary>
        public void Clear()
        {
            started = false;
            Tower.Clear(); Dungeons.Clear(); Raid.Clear(); Descent.Clear(); RiftAtlas.Clear(); WaystoneAtlas.Clear(); Invasion.Clear();
            Siege.Clear(); Arena.Clear(); Battleground.Clear(); PvpZone.Clear(); Bounty.Clear();
        }
    }
}
