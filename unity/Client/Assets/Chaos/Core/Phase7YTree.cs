// Phase 7, track Y: the passive tree window's Paragon panel (port of game_passivetree paragon.lua and paragonmath.lua) and another character's tree
// shown read-only (viewother.lua). Server: paragon.lua (extended opcode 65):
//   client -> server  paragonRequest | paragonApply {alloc: {statKey: points}} | paragonReset
//   server -> client  paragonState {unlocked, level, startLevel, total, spent, free, resetCost, categories [{key, name, stats [{key, name, desc, perPoint, maxPoints, points}]}]}
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public sealed class ParagonStat
    {
        public string Key = "", Name = "", Desc = "";
        public double PerPoint;
        public int MaxPoints, Points;
    }

    public sealed class ParagonCategory
    {
        public string Key = "", Name = "";
        public readonly List<ParagonStat> Stats = new List<ParagonStat>();
    }

    public sealed class ParagonPanel
    {
        readonly ExtOpcodes ext;
        public bool Known, Unlocked;
        public int Level, StartLevel = 1000, Total, Spent, FreePoints;
        public long ResetCost;
        public readonly List<ParagonCategory> Categories = new List<ParagonCategory>();
        /// <summary>Points added in the panel and not applied yet, by stat key.</summary>
        public readonly Dictionary<string, int> Pending = new Dictionary<string, int>();
        public Action Changed = delegate { };

        public ParagonPanel(ExtOpcodes e) { ext = e; }

        public void Request() { ext.Send(PassiveTree.Opcode, "paragonRequest", null); }

        public void Receive(object data)
        {
            if (!(data is Dictionary<string, object>)) return;
            Known = true;
            Unlocked = Json.Bool(data, "unlocked");
            Level = Json.Int(data, "level"); StartLevel = Json.Int(data, "startLevel", 1000);
            Total = Json.Int(data, "total"); Spent = Json.Int(data, "spent"); FreePoints = Json.Int(data, "free");
            ResetCost = (long)Json.Number(data, "resetCost");
            Categories.Clear();
            foreach (object c in Json.List(data, "categories"))
            {
                var cat = new ParagonCategory { Key = Json.Text(c, "key"), Name = Json.Text(c, "name") };
                foreach (object s in Json.List(c, "stats"))
                    cat.Stats.Add(new ParagonStat { Key = Json.Text(s, "key"), Name = Json.Text(s, "name"), Desc = Json.Text(s, "desc"), PerPoint = Json.Number(s, "perPoint"), MaxPoints = Json.Int(s, "maxPoints"), Points = Json.Int(s, "points") });
                Categories.Add(cat);
            }
            Pending.Clear();
            Changed();
        }

        // ---- paragonmath.lua
        public int PendingSum() { int n = 0; foreach (int v in Pending.Values) n += v; return n; }
        public int Free() => Math.Max(0, FreePoints - PendingSum());
        public int PointsOf(ParagonStat s) { int p; return s.Points + (Pending.TryGetValue(s.Key, out p) ? p : 0); }
        public bool CanAdd(ParagonStat s) => Known && Unlocked && Free() > 0 && PointsOf(s) < s.MaxPoints;
        public bool CanRemove(ParagonStat s) { int p; return Pending.TryGetValue(s.Key, out p) && p > 0; }

        /// <summary>Adds up to n points (limited by the free points and the room of the stat); returns how many were added.</summary>
        public int Add(ParagonStat s, int n = 1)
        {
            if (!CanAdd(s)) return 0;
            int k = Math.Min(n, Math.Min(s.MaxPoints - PointsOf(s), Free()));
            if (k <= 0) return 0;
            int have; Pending.TryGetValue(s.Key, out have);
            Pending[s.Key] = have + k;
            Changed();
            return k;
        }

        /// <summary>Removes up to n pending points (applied points only go with a reset); returns how many were removed.</summary>
        public int Remove(ParagonStat s, int n = 1)
        {
            int have;
            if (!Pending.TryGetValue(s.Key, out have) || have <= 0) return 0;
            int k = Math.Min(n, have);
            if (have - k > 0) Pending[s.Key] = have - k; else Pending.Remove(s.Key);
            Changed();
            return k;
        }

        /// <summary>The absolute allocation of paragonApply ({} when nothing is pending).</summary>
        public Dictionary<string, object> Alloc()
        {
            var o = new Dictionary<string, object>();
            foreach (var c in Categories)
                foreach (var s in c.Stats)
                    if (Pending.TryGetValue(s.Key, out int p) && p > 0) o[s.Key] = PointsOf(s);
            return o;
        }

        public bool Apply()
        {
            if (!Known || PendingSum() <= 0) return false;
            ext.Send(PassiveTree.Opcode, "paragonApply", new Dictionary<string, object> { { "alloc", Alloc() } });
            return true;
        }

        public bool Reset()
        {
            if (!Known || Spent <= 0) return false;
            ext.Send(PassiveTree.Opcode, "paragonReset", null);
            return true;
        }

        /// <summary>0.25 to "0.25", 1.5 to "1.5", 20 to "20".</summary>
        public static string Fmt(double v)
        {
            string s = v.ToString("0.00", CultureInfo.InvariantCulture);
            s = s.TrimEnd('0');
            if (s.EndsWith(".", StringComparison.Ordinal)) s = s.Substring(0, s.Length - 1);
            return s;
        }

        public static double Value(ParagonStat s, int points) => s.PerPoint * Math.Max(0, Math.Min(points, s.MaxPoints));

        /// <summary>"+1.5% / 20%".</summary>
        public static string ValueText(ParagonStat s, int points) => "+" + Fmt(Value(s, points)) + "% / " + Fmt(s.PerPoint * s.MaxPoints) + "%";

        public static string Tip(ParagonStat s) =>
            (s.Desc.Length > 0 ? s.Desc : s.Name) + "\n" + Loc.T("+{0}% per point, up to +{1}% ({2} points).", Fmt(s.PerPoint), Fmt(s.PerPoint * s.MaxPoints), s.MaxPoints);

        /// <summary>The summary line: available, spent (with the pending ones) and total.</summary>
        public string Summary()
        {
            if (!Unlocked) return Loc.T("Level {0}", Level);
            int p = PendingSum();
            return Loc.T("Available: {0}     Spent: {1}     Total: {2}", Free(), (Spent + p) + (p > 0 ? " (+" + p + ")" : ""), Total);
        }

        public string LockedTitle => Loc.T("Unlocks at level {0}", StartLevel);
        public string LockedText => Loc.T("Every level above {0} gives one Paragon point for small, capped bonuses: damage, health, speed, gold and item find.", StartLevel);
        public string ResetTip => Loc.T("Refund every Paragon point for {0} gold (level x 250).", ResetCost);
        public string ResetAsk => Loc.T("Refund all {0} Paragon points for {1}? Proceed?", Spent, ResetCost > 0 ? Loc.T("{0} gold coins", ResetCost.ToString("N0", CultureInfo.InvariantCulture)) : Loc.T("free"));

        /// <summary>The applied bonuses, one line each ("+1.5% Damage (Paragon).").</summary>
        public List<string> BonusLines()
        {
            var l = new List<string>();
            foreach (var c in Categories) foreach (var s in c.Stats) if (s.Points > 0) l.Add(Loc.T("+{0}% {1} (Paragon).", Fmt(Value(s, s.Points)), s.Name));
            return l;
        }
    }

    /// <summary>Another character's tree on show (the main client's setTreeViewing banner).</summary>
    public sealed class TreeViewing
    {
        public string Name = "";
        public int Count, Spent, Total;

        /// <summary>"Name: 12 passive nodes (read-only)".</summary>
        public string Banner => Loc.T(Count == 1 ? "{0}: {1} passive node (read-only)" : "{0}: {1} passive nodes (read-only)", Name, Count);

        /// <summary>The own allocation, put aside while another tree shows.</summary>
        public sealed class OwnState
        {
            HashSet<int> allocated;
            Dictionary<int, int> masteries;
            string cls = "", line = "", vocation = "";

            public static OwnState Take(PassiveTree t) => new OwnState
            {
                allocated = new HashSet<int>(t.Allocated), masteries = new Dictionary<int, int>(t.Masteries), cls = t.Cls, line = t.Line, vocation = t.Vocation,
            };

            public void Restore(PassiveTree t)
            {
                t.Allocated.Clear(); foreach (int i in allocated) t.Allocated.Add(i);
                t.Masteries.Clear(); foreach (var kv in masteries) t.Masteries[kv.Key] = kv.Value;
                t.Cls = cls; t.Line = line; t.Vocation = vocation;
            }
        }
    }
}
