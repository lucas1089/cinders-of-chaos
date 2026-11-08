// Phase 7, track Z: game_codex in pt-BR (game_codex/codextext.lua). The generated English Codex is full of numbers that change with the server's data, so a text is looked up
// with its numbers taken out: every number becomes %s and every % becomes %%, the result is the key (CodexTextData.Table, generated from pt_br.lua) and the numbers fill the
// translation's %s again. A text without an entry stays as it was (English): names of items, orbs and monsters and the long one-off paragraphs. Pure.
using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core
{
    public static class CodexText
    {
        static readonly Regex Number = new Regex(@"\d+\.?\d*", RegexOptions.Compiled);

        /// <summary>The table of the chosen language (null: English, every text as it is). Tests set their own.</summary>
        public static Func<IDictionary<string, string>> Source = () => Loc.Language == Loc.Portuguese ? CodexTextData.Table : null;

        /// <summary>The key of a text and its numbers as written: "Cap: at most 15% ..." gives "Cap: at most %s%% ..." and {"15"}.</summary>
        public static string Key(string text, out List<string> nums)
        {
            var found = new List<string>();
            string key = Number.Replace((text ?? "").Replace("%", "%%"), m =>
            {
                string n = m.Value, dot = "";
                if (n.EndsWith(".", StringComparison.Ordinal)) { n = n.Substring(0, n.Length - 1); dot = "."; }   // a number ends before the dot of a sentence
                found.Add(n);
                return "%s" + dot;
            });
            nums = found;
            return key;
        }

        /// <summary>A translation's %s filled with the numbers in order, %% as %.</summary>
        public static string Fill(string translated, IList<string> nums)
        {
            var sb = new StringBuilder();
            int k = 0;
            for (int i = 0; i < translated.Length; i++)
            {
                char c = translated[i];
                if (c == '%' && i + 1 < translated.Length)
                {
                    char n = translated[i + 1];
                    if (n == 's') { sb.Append(k < nums.Count ? nums[k] : ""); k++; i++; continue; }
                    if (n == '%') { sb.Append('%'); i++; continue; }
                }
                sb.Append(c);
            }
            return sb.ToString();
        }

        static bool Lookup(string text, out string shown)
        {
            shown = text;
            var table = Source();
            if (table == null) return false;
            string key = Key(text, out var nums);
            if (!table.TryGetValue(key, out var tr)) return false;
            shown = Fill(tr, nums);
            return true;
        }

        /// <summary>The text in the client's language, as it was without an entry.</summary>
        public static string T(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            Lookup(text, out string shown);
            return shown;
        }

        // the parts of a comma separated list, longest known span first (up to 4 parts)
        static string Parts(string text)
        {
            var list = new List<string>();
            foreach (var p in (text + ", ").Split(new[] { ", " }, StringSplitOptions.None)) list.Add(p);
            list.RemoveAt(list.Count - 1);   // the empty piece after the last ", "
            var o = new List<string>();
            int i = 0;
            while (i < list.Count)
            {
                int used = 1;
                string shown = null;
                for (int span = Math.Min(4, list.Count - i); span >= 1; span--)
                {
                    string candidate = string.Join(", ", list.GetRange(i, span));
                    if (Lookup(candidate, out string s)) { used = span; shown = s; break; }
                }
                o.Add(shown ?? list[i]);
                i += used;
            }
            return string.Join(", ", o);
        }

        /// <summary>A list line ("Suffix, any gear. +2% (T1) to +10-14% (T8)"): the whole line when known, else its sentences and their comma separated parts one by one, the numbers kept.</summary>
        public static string Sub(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            if (Lookup(text, out string whole)) return whole;
            if (Source() == null) return text;
            string body = text.EndsWith(".", StringComparison.Ordinal) ? text.Substring(0, text.Length - 1) : text;
            var sentences = new List<string>();
            foreach (var s in (body + ". ").Split(new[] { ". " }, StringSplitOptions.None)) sentences.Add(s);
            sentences.RemoveAt(sentences.Count - 1);
            for (int i = 0; i < sentences.Count; i++)
            {
                string shown = Parts(sentences[i]);
                // "+2% (T1) to +10% (T8)": the word between the two ends of the range
                shown = Regex.Replace(shown, @" \(T(\d+)\) to ", m => T(" (T" + m.Groups[1].Value + ") to "));
                sentences[i] = shown;
            }
            string o = string.Join(". ", sentences);
            return text.EndsWith(".", StringComparison.Ordinal) ? o + "." : o;
        }
    }
}
