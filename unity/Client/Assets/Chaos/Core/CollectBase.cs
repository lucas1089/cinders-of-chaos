// Shared base of the collection, season and crafting models (O433 phase 4, track N): one extended opcode, {action, data} both ways,
// a Changed callback for the window, and the number and list helpers the main client's *view.lua files repeat (num, group, short, rows).
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    /// <summary>A model of one opcode. Handle gets every message, Changed fires after it.</summary>
    public abstract class CollectModel
    {
        protected readonly ExtOpcodes Ext;
        public readonly byte Opcode;
        public Action Changed = delegate { };
        /// <summary>Session clock in ms (timers).</summary>
        public Func<double> Clock = () => 0;

        protected CollectModel(ExtOpcodes e, byte opcode)
        {
            Ext = e;
            Opcode = opcode;
            Ext.On(opcode, m => { HandleMessage(m); Changed(); });
        }

        /// <summary>The whole decoded message (a model with its own wrapper, like the crafting table, overrides this).</summary>
        protected virtual void HandleMessage(ExtMessage m) { Handle(m.Action, m.Data ?? new Dictionary<string, object>()); }

        public abstract void Handle(string action, object data);

        protected bool Send(string action, Dictionary<string, object> data = null)
        {
            return Ext.Send(Opcode, action, data ?? new Dictionary<string, object>());
        }

        protected static Dictionary<string, object> D(params object[] kv)
        {
            var d = new Dictionary<string, object>();
            for (int i = 0; i + 1 < kv.Length; i += 2) d[(string)kv[i]] = kv[i + 1];
            return d;
        }

        /// <summary>Stable sort (List.Sort is not).</summary>
        public static List<T> StableSort<T>(IEnumerable<T> src, Comparison<T> cmp)
        {
            var copy = new List<T>(src);
            for (int i = 1; i < copy.Count; i++)
            {
                var x = copy[i]; int j = i - 1;
                while (j >= 0 && cmp(copy[j], x) > 0) { copy[j + 1] = copy[j]; j--; }
                copy[j + 1] = x;
            }
            return copy;
        }
    }

    /// <summary>Helpers of the *view.lua files: tonumber with 0, thousands groups, k / M, plural, rows of tables only.</summary>
    public static class CF
    {
        public static double Num(object o) => o is double d && !double.IsNaN(d) ? d : o is string s && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : 0;
        public static int Int(object o) => (int)Math.Max(int.MinValue, Math.Min(int.MaxValue, Num(o)));
        public static long Long(object o) => (long)Num(o);
        public static string Str(object o, string fallback = "") => o is string s ? s : o is double d ? d.ToString("0.##", CultureInfo.InvariantCulture) : fallback;
        public static bool On(object o) => Json.Truthy(o);

        /// <summary>The entries of a list that are tables (the main client's list()).</summary>
        public static List<Dictionary<string, object>> Rows(object o)
        {
            var r = new List<Dictionary<string, object>>();
            if (o is List<object> l) foreach (var x in l) if (x is Dictionary<string, object> m) r.Add(m);
            return r;
        }

        public static List<object> Raw(object o) => o as List<object> ?? new List<object>();

        /// <summary>Strings and numbers of a list as text (values()).</summary>
        public static List<string> Values(object o)
        {
            var r = new List<string>();
            if (o is List<object> l) foreach (var x in l) if (x is string || x is double) r.Add(Str(x));
            return r;
        }

        public static object G(object o, string k) => Json.Get(o, k);
        public static string T(object o, string k, string f = "") => Json.Text(o, k, f);
        public static int I(object o, string k) => Int(Json.Get(o, k));
        public static double N(object o, string k) => Num(Json.Get(o, k));
        public static bool B(object o, string k) => On(Json.Get(o, k));
        public static Dictionary<string, object> M(object o, string k) => Json.Get(o, k) as Dictionary<string, object> ?? new Dictionary<string, object>();

        /// <summary>1234567 -> "1,234,567".</summary>
        public static string Group(double n) => ((long)Math.Floor(n)).ToString("#,0", CultureInfo.InvariantCulture);

        /// <summary>1500 -> "1.5k", 2000000 -> "2M" (the bestiary's short).</summary>
        public static string Short(double n)
        {
            if (n >= 1000000) { double v = n / 1000000; return v == Math.Floor(v) ? ((long)v) + "M" : v.ToString("0.0", CultureInfo.InvariantCulture) + "M"; }
            if (n >= 1000) { double v = n / 1000; return v == Math.Floor(v) ? ((long)v) + "k" : v.ToString("0.0", CultureInfo.InvariantCulture) + "k"; }
            return ((long)Math.Floor(n)).ToString(CultureInfo.InvariantCulture);
        }

        /// <summary>12 -> "12%", 12.5 -> "12.5%".</summary>
        public static string Pct(double p) => p == Math.Floor(p) ? ((long)p) + "%" : p.ToString("0.0", CultureInfo.InvariantCulture) + "%";

        public static int Percent(double value, double total)
        {
            if (total <= 0) return 0;
            return (int)Math.Max(0, Math.Min(100, Math.Floor(value * 100 / total)));
        }

        /// <summary>Seconds -> "3h 05m" (hours and minutes).</summary>
        public static string HoursMinutes(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            return string.Format(CultureInfo.InvariantCulture, "{0}h {1:00}m", s / 3600, s % 3600 / 60);
        }

        /// <summary>Unix seconds -> "2025-03-01" (UTC), "" for none.</summary>
        public static string Date(double at)
        {
            if (at <= 0) return "";
            return new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(at).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }

        public static string Hex(object o) => o is string s ? s : null;
    }
}
