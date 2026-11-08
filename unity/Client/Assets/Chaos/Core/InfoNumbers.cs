// Short numbers for everything the client shows: 1000 -> 1k, 15300 -> 15.3k, 2450000 -> 2.45M, 1200000000 -> 1.2B (O433 phase 5, track Q).
// A port of client_chaos_numbers/numbers.lua: formatShortNumber, formatExactNumber, shortNumbersIn (a conservative text rule: a number is shortened only
// when it stands alone, so ids, coordinates, years, times and parts of words stay as they are) and shortNumbersInMessage (only the server message kinds
// that carry damage, healing, experience, look and status text). The rule is the one of the numbers above the map: three significant digits, trailing
// zeros dropped, rounded down (999999 is 999k, never 1000k), below 1000 the number as it is, a negative number keeps its sign, integer arithmetic only.
// Tests: Core.Tests/InfoTests.cs (mirrors numbers_test.lua).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core
{
    public static class ShortNumbers
    {
        /// <summary>False turns the shortening of server messages off (the numbers a window formats itself stay short).</summary>
        public static bool Enabled = true;

        static readonly string[] Units = { "", "k", "M", "B", "T" };

        /// <summary>1150 is 1.15k, 150000 is 150k.</summary>
        public static string Short(double n)
        {
            if (double.IsNaN(n) || double.IsInfinity(n)) return n.ToString(CultureInfo.InvariantCulture);
            double v = n;
            string sign = "";
            if (v < 0) { sign = "-"; v = -v; }
            if (v < 1000) return sign + (v == Math.Floor(v) ? ((long)v).ToString(CultureInfo.InvariantCulture) : v.ToString("R", CultureInfo.InvariantCulture));
            long value = (long)Math.Floor(v);
            int unit = 0;
            long div = 1;
            while (unit < Units.Length - 1 && value / div >= 1000) { div *= 1000; unit++; }
            long whole = value / div;
            int decimals = whole >= 100 ? 0 : (whole >= 10 ? 1 : 2);
            string text;
            if (decimals == 0) text = whole.ToString(CultureInfo.InvariantCulture);
            else
            {
                int factor = decimals == 2 ? 100 : 10;
                long scaled = value / (div / factor);
                long frac = scaled - whole * factor;
                text = whole.ToString(CultureInfo.InvariantCulture) + "." + frac.ToString(new string('0', decimals), CultureInfo.InvariantCulture);
                text = text.TrimEnd('0').TrimEnd('.');
            }
            return sign + text + Units[unit];
        }

        /// <summary>15300 is 15,300 (for tooltips that show the exact value).</summary>
        public static string Exact(double n)
        {
            if (double.IsNaN(n) || double.IsInfinity(n)) return n.ToString(CultureInfo.InvariantCulture);
            string text = n == Math.Floor(n) ? ((long)n).ToString(CultureInfo.InvariantCulture) : n.ToString("R", CultureInfo.InvariantCulture);
            string sign = "";
            if (text.StartsWith("-")) { sign = "-"; text = text.Substring(1); }
            int dot = text.IndexOf('.');
            string whole = dot >= 0 ? text.Substring(0, dot) : text, rest = dot >= 0 ? text.Substring(dot) : "";
            var sb = new StringBuilder();
            for (int i = 0; i < whole.Length; i++)
            {
                if (i > 0 && (whole.Length - i) % 3 == 0) sb.Append(',');
                sb.Append(whole[i]);
            }
            return sign + sb + rest;
        }

        // ------------------------------------------------------------------------------------ text
        // Left as it is: glued to letters, digits, '_', '#', '@' or '\' (ids, colours, '2304a', '#123', 'x1500', '1500gp'), next to ':' (times 02:44:36),
        // a decimal or an already short number (12.5, 1.5k), a list or coordinates without spaces (32369,32241,7), any number of a 'a, b, c' triple, a number
        // after a keyword such as id, x, y, z, pos, port, version, a range or date part ('2026-10-08', '1000-2000'), a year 1900..2100 next to a month
        // name or the word 'year', a number with leading zeros, '[1234]', the item id of the loot markup '{3031|gold coin}'.
        // Thousands separators are understood: '1,234,567' and '1.234.567' (dots need two groups; '1.234' is left).
        static readonly HashSet<string> Keywords = new HashSet<string>
        {
            "id", "ids", "uid", "aid", "cid", "sid", "actionid", "uniqueid", "itemid", "clientid", "serverid", "x", "y", "z", "pos", "position", "coord", "coords",
            "coordinates", "port", "version", "ver", "protocol", "code", "pin", "ticket", "nr", "serial", "build", "opcode",
        };

        static readonly HashSet<string> Months = new HashSet<string>
        {
            "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec", "january", "february", "march", "april", "june", "july",
            "august", "september", "october", "november", "december", "year", "years",
        };

        static bool IsWord(string c) => !string.IsNullOrEmpty(c) && (char.IsLetterOrDigit(c[0]) && c[0] < 128 || c[0] == '_' || c[0] >= 128);
        static bool IsDigit(string c) => !string.IsNullOrEmpty(c) && c[0] >= '0' && c[0] <= '9';
        static bool IsAlpha(char c) => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');

        static string At(string t, int i) => i >= 0 && i < t.Length ? t[i].ToString() : "";

        static readonly Regex TrailingSep = new Regex(@"\s*[:=#\.]?\s*\z");
        static readonly Regex LastWord = new Regex(@"([A-Za-z]+)\z");
        static readonly Regex DayAfterMonth = new Regex(@"([A-Za-z]+)\s+\d\d?\s*,?\z");
        static readonly Regex DayBeforeMonth = new Regex(@"\d\d?\s+([A-Za-z]+)\s*,?\z");
        static readonly Regex WordAfterRx = new Regex(@"\G[\s,]*([A-Za-z]+)");
        static readonly Regex Triple = new Regex(@"\d+\s*,\s*\d+\s*,\s*\d+");
        static readonly Regex Grouped = new Regex(@"\A\d\d?\d?,\d\d\d,\d\d\d\z");
        static readonly Regex NumberRun = new Regex(@"\G[\d\.,]*\d");

        // the last word before index i and the text before it (a space, one ':', '=', '#' or '.' skipped)
        static string WordBefore(string text, int i, out string head)
        {
            int from = Math.Max(0, i - 40);
            head = TrailingSep.Replace(text.Substring(from, i - from), "");
            var m = LastWord.Match(head);
            return m.Success ? m.Groups[1].Value.ToLowerInvariant() : null;
        }

        static string WordAfter(string text, int j)
        {
            var m = WordAfterRx.Match(text, j);
            return m.Success ? m.Groups[1].Value.ToLowerInvariant() : null;
        }

        static bool LooksLikeYear(string text, int s, int e, string digits)
        {
            if (digits.Length != 4) return false;
            int n = int.Parse(digits, CultureInfo.InvariantCulture);
            if (n < 1900 || n > 2100) return false;
            string head;
            string before = WordBefore(text, s, out head);
            if (before != null && Months.Contains(before)) return true;
            var a = DayAfterMonth.Match(head);
            var b = DayBeforeMonth.Match(head);
            string monthDay = a.Success ? a.Groups[1].Value : b.Success ? b.Groups[1].Value : null;
            if (monthDay != null && Months.Contains(monthDay.ToLowerInvariant())) return true;
            string after = WordAfter(text, e);
            return after != null && Months.Contains(after) && after != "year" && after != "years";
        }

        // scans a number starting at s: its end (exclusive) and the digits only (thousands separators folded in)
        static int ScanNumber(string text, int s, out string digits)
        {
            int plainEnd = s;
            while (plainEnd < text.Length && text[plainEnd] >= '0' && text[plainEnd] <= '9') plainEnd++;
            int e = plainEnd;
            digits = text.Substring(s, plainEnd - s);
            if (digits.Length <= 3)
            {
                foreach (char sep in new[] { ',', '.' })
                {
                    int j = plainEnd, groups = 0;
                    string collected = digits;
                    while (j + 3 < text.Length && text[j] == sep && IsDigit(At(text, j + 1)) && IsDigit(At(text, j + 2)) && IsDigit(At(text, j + 3)) && !IsDigit(At(text, j + 4)))
                    {
                        collected += text.Substring(j + 1, 3);
                        j += 4;
                        groups++;
                    }
                    if (groups >= (sep == ',' ? 1 : 2)) { e = j; digits = collected; break; }
                }
            }
            return e;
        }

        static bool CanShorten(string text, int s, int e, string digits)
        {
            if (digits.Length < 4 || digits[0] == '0') return false;
            string prev = At(text, s - 1), prev2 = At(text, s - 2), next = At(text, e), next2 = At(text, e + 1);
            if (IsWord(prev) || (prev != "" && "#@\\:.,/".IndexOf(prev[0]) >= 0)) return false;
            if (prev == "-" && (IsWord(prev2) || (prev2 != "" && "-/".IndexOf(prev2[0]) >= 0))) return false;
            if (IsWord(next) || (next != "" && "#@\\|".IndexOf(next[0]) >= 0)) return false;
            if (next != "" && ":.,/-".IndexOf(next[0]) >= 0 && (IsDigit(next2) || IsWord(next2))) return false;
            if (prev == "[" && next == "]") return false;
            string head;
            string before = WordBefore(text, s, out head);
            if (before != null && Keywords.Contains(before)) return false;
            return !LooksLikeYear(text, s, e, digits);
        }

        static bool[] TriplePositions(string text)
        {
            var skip = new bool[text.Length];
            int init = 0;
            while (init <= text.Length)
            {
                var m = Triple.Match(text, init);
                if (!m.Success) break;
                // a grouped number such as '1,234,567' is not a triple: it has no space and groups of three digits
                if (!Grouped.IsMatch(m.Value)) for (int i = m.Index; i < m.Index + m.Length; i++) skip[i] = true;
                init = m.Index + m.Length;
            }
            return skip;
        }

        /// <summary>The text with every standalone integer of 1000 or more shortened.</summary>
        public static string In(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            if (!Regex.IsMatch(text, @"\d\d\d")) return text;
            var skip = TriplePositions(text);
            var sb = new StringBuilder();
            int i = 0, len = text.Length;
            while (i < len)
            {
                int s = i;
                while (s < len && !(text[s] >= '0' && text[s] <= '9')) s++;
                if (s >= len) { sb.Append(text, i, len - i); break; }
                sb.Append(text, i, s - i);
                string digits;
                int e = ScanNumber(text, s, out digits);
                if (!skip[s] && CanShorten(text, s, e, digits)) sb.Append(Short(double.Parse(digits, CultureInfo.InvariantCulture)));
                else
                {
                    // leave the whole run of digits and separators as it is ('1.5k', '32369,32241,7', '1234.56')
                    var run = NumberRun.Match(text, s);
                    int runEnd = run.Success ? run.Index + run.Length : e;
                    e = Math.Max(e, runEnd);
                    sb.Append(text, s, e - s);
                }
                i = e;
            }
            return sb.ToString();
        }

        // the 10.98 server message kinds whose text is shortened: status (17 white, 18 red, 21 small), event advance (19) and look / info (22)
        static readonly HashSet<int> MessageKinds = new HashSet<int> { 17, 18, 19, 21, 22 };

        /// <summary>The text of a server message of that kind with its numbers shortened; chat, private, NPC talk, broadcasts and login text stay as they are.</summary>
        public static string InMessage(int kind, string text) => Enabled && MessageKinds.Contains(kind) ? In(text) : text;
    }
}
