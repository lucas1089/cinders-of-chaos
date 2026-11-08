// Help search (O433 phase 5, track Q): offline, no server and no AI call. The player types a question or a few words ("how do I get orbs", "gems", "como subir de
// nivel") and gets the best answers of three sources: the "How it works" cards (with the card's keywords, level and top menu path, and its unlock entries), an
// unlock entry with no card, and the Codex entries (English only). A port of game_helpsearch/helpcore.lua; the data is Resources/HelpSearch.json (generated from
// helpsearch_data.lua by unity/tools/gen_info_data.lua, which server/tools/gen_guide_data.lua writes), the cards are HowItWorks and the Codex is Codex.
// Ranking: each word of the query is folded (lower case, accents off, so "nivel" finds "nivel" with an accent), plurals cut, small words dropped, then looked up in the
// title (10), the keywords and tab (6) and the text (2); a word that starts a longer word counts less, a synonym 0.7 of it. A result that holds every word scores
// more; a title that holds every word more again; cards come before the Codex. A query that asks where something comes from (get, farm, ganhar) weighs a card's
// "What drops" row like a title and the Codex less.
// Tests: Core.Tests/InfoTests.cs (mirrors helpcore_test.lua).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace Chaos.Core
{
    public sealed class HelpPair { public string En = "", Pt = ""; public HelpPair() { } public HelpPair(string en, string pt) { En = en; Pt = pt; } }

    public sealed class HelpDoc
    {
        public string Kind = "", Key = "", Menu = "", Tab = "";
        public HelpPair Title = new HelpPair();
        public int? Level;
        public readonly List<HelpPair> Texts = new List<HelpPair>();
        /// <summary>Stems of the title, of the keywords / tab / menu / row headings, of the text, and of the "What drops" row of a card.</summary>
        public readonly HashSet<string> T = new HashSet<string>(), G = new HashSet<string>(), B = new HashSet<string>(), D = new HashSet<string>();
    }

    public sealed class HelpResult { public HelpDoc Doc; public double Score; }

    public sealed class HelpStep { public HelpDoc Doc; public HelpPair Tip; }

    public sealed class HelpIndex
    {
        public readonly List<HelpDoc> Docs = new List<HelpDoc>();
        public readonly Dictionary<string, HelpDoc> Cards = new Dictionary<string, HelpDoc>();
        public readonly List<HelpStep> Steps = new List<HelpStep>();
        public HelpPair Intro = new HelpPair();
    }

    public static class HelpSearch
    {
        public const double WTitle = 10, WTag = 6, WBody = 2, WPrefix = 0.6, WSynonym = 0.7, WAllInTitle = 4, WSource = 9, KindSourceCodex = 0.6;
        public const int Limit = 8, Snippet = 80;

        static double KindWeight(string kind) => kind == "card" ? 1.0 : kind == "unlock" ? 0.95 : 0.85;

        // ------------------------------------------------------------------------------------ folding
        static readonly Dictionary<char, char> Latin = BuildLatin();

        static Dictionary<char, char> BuildLatin()
        {
            var m = new Dictionary<char, char>();
            Action<char, string> add = (b, chars) => { foreach (char c in chars) m[c] = b; };
            add('a', "àáâãäåÀÁÂÃÄÅ");
            add('e', "èéêëÈÉÊË");
            add('i', "ìíîïÌÍÎÏ");
            add('o', "òóôõöÒÓÔÕÖ");
            add('u', "ùúûüÙÚÛÜ");
            add('c', "çÇ"); add('n', "ñÑ"); add('y', "ýÿÝ");
            return m;
        }

        /// <summary>Lower case ASCII; accents off; any other character becomes a space.</summary>
        public static string Fold(string s)
        {
            var sb = new StringBuilder();
            foreach (char c in s ?? "")
            {
                if (c < 0x80) sb.Append(char.ToLowerInvariant(c));
                else { char b; sb.Append(Latin.TryGetValue(c, out b) ? b : ' '); }
            }
            return sb.ToString();
        }

        // ------------------------------------------------------------------------------------ words
        static readonly HashSet<string> Stop = new HashSet<string>((
            "a an the of to in on at by for from with and or is are was be it its this that these those my me i you your we our how do does did can could what which where when who why will " +
            "would should get got have has there here any some about into than then so if not no up out more most very much many happen happens acontece " +
            "o os as um uma uns umas de do da dos das no na nos nas em ao aos e ou que como onde quando quem qual quais por para pra com sem se eu meu minha meus minhas voce seu sua " +
            "seus suas ele ela isso isto esse essa este esta ja mais muito muitos tem ter faco fazer consigo pegar posso pode").Split(' '));

        /// <summary>Plural and simple endings off, the same for the data and the query.</summary>
        public static string Stem(string w)
        {
            int n = w.Length;
            if (n <= 3) return w;
            if (n > 4 && w.EndsWith("oes")) return w.Substring(0, n - 3) + "ao";
            if (n > 4 && w.EndsWith("eis")) return w.Substring(0, n - 3) + "el";
            if (n > 4 && w.EndsWith("ies")) return w.Substring(0, n - 3) + "y";
            if (w.EndsWith("ns")) return w.Substring(0, n - 2) + "m";
            if (w.EndsWith("s") && !w.EndsWith("ss")) return w.Substring(0, n - 1);
            return w;
        }

        static IEnumerable<string> Words(string folded)
        {
            var sb = new StringBuilder();
            foreach (char c in folded + " ")
            {
                if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) sb.Append(c);
                else if (sb.Length > 0) { yield return sb.ToString(); sb.Clear(); }
            }
        }

        /// <summary>The stems of a text, in order, small words out (duplicates kept).</summary>
        public static List<string> Tokens(string s)
        {
            var o = new List<string>();
            foreach (var w in Words(Fold(s)))
                if (!Stop.Contains(w) && (w.Length > 1 || (w[0] >= '0' && w[0] <= '9'))) o.Add(Stem(w));
            return o;
        }

        // ------------------------------------------------------------------------------------ synonyms (en and pt; stems after fold)
        static readonly string[][] SynonymGroups =
        {
            new[] { "level", "nivel", "lvl", "leveling", "upar", "subir", "evoluir" }, new[] { "experience", "experiencia", "exp", "xp" }, new[] { "orb", "orbe" },
            new[] { "gem", "gema", "socket", "engaste" }, new[] { "rift", "fenda" }, new[] { "dungeon", "masmorra" }, new[] { "boss", "chefe", "chefao" },
            new[] { "death", "die", "dead", "morte", "morrer", "morri", "morro" }, new[] { "gold", "ouro", "money", "dinheiro", "coin", "moeda" },
            new[] { "item", "gear", "equipment", "equipamento" }, new[] { "craft", "crafting", "upgrade", "melhorar", "forjar" }, new[] { "salvage", "reciclar", "reciclagem" },
            new[] { "pet", "mascote" }, new[] { "guild", "guilda", "clan", "cla" }, new[] { "party", "group", "grupo", "team", "time" }, new[] { "store", "shop", "loja" },
            new[] { "market", "mercado", "sell", "vender", "buy", "comprar" }, new[] { "tower", "torre" }, new[] { "pvp", "arena", "battleground" },
            new[] { "daily", "diario", "diaria" }, new[] { "weekly", "semanal" }, new[] { "chest", "bau" }, new[] { "spell", "magia", "feitico" },
            new[] { "passive", "passiva", "tree", "arvore" }, new[] { "loot", "saque", "drop" }, new[] { "faction", "faccao" }, new[] { "season", "temporada" },
            new[] { "mount", "montaria" }, new[] { "outfit", "traje", "roupa" }, new[] { "achievement", "conquista" }, new[] { "hunt", "cacar", "caca", "cacada" },
            new[] { "monster", "monstro", "mob" }, new[] { "potion", "pocao" }, new[] { "teleport", "teletransporte", "portal" },
            new[] { "town", "city", "cidade", "temple", "templo" }, new[] { "invasion", "invasao" }, new[] { "siege", "cerco" },
            new[] { "bounty", "contract", "contrato", "task", "tarefa" }, new[] { "gamble", "gambler", "aposta", "apostador" }, new[] { "profession", "profissao" },
            new[] { "charm", "amuleto" }, new[] { "bestiary", "bestiario" }, new[] { "hideout", "esconderijo" },
            new[] { "storage", "stash", "depot", "deposito", "guardar" }, new[] { "transmog", "aparencia", "look", "visual" },
            new[] { "mentor", "apprentice", "aprendiz", "veteran", "veterano" },
        };

        static readonly Dictionary<string, List<string>> Syn = BuildSyn();

        static Dictionary<string, List<string>> BuildSyn()
        {
            var syn = new Dictionary<string, List<string>>();
            foreach (var group in SynonymGroups)
            {
                var stems = group.Select(w => Stem(Fold(w))).ToList();
                foreach (var a in stems)
                {
                    if (!syn.ContainsKey(a)) syn[a] = new List<string>();
                    foreach (var b in stems) if (b != a) syn[a].Add(b);
                }
            }
            return syn;
        }

        /// <summary>stem to weight: the word itself 1, its synonyms WSynonym.</summary>
        public static Dictionary<string, double> Expand(string stem)
        {
            var o = new Dictionary<string, double> { { stem, 1 } };
            List<string> list;
            if (Syn.TryGetValue(stem, out list)) foreach (var s in list) if (!o.ContainsKey(s)) o[s] = WSynonym;
            return o;
        }

        // the words of a card row's heading: a card with that row answers them
        static readonly Dictionary<string, string> RowWords = new Dictionary<string, string>
        {
            { "death", "die dies death dead lose penalty morrer morte morri perder" }, { "drops", "drops loot reward prize saque recompensa premio" },
            { "often", "often times limit cooldown wait vezes limite espera" }, { "levels", "monster monstro" },
        };

        static readonly HashSet<string> SourceWords = new HashSet<string>(
            "get gets obtain farm earn source sources find ganhar obter conseguir farmar arrumar achar pegar vem".Split(' '));

        // ------------------------------------------------------------------------------------ the index
        static void AddSet(HashSet<string> set, string text) { foreach (var t in Tokens(text)) set.Add(t); }

        static HelpDoc NewDoc(string kind, string key, HelpPair title) => new HelpDoc { Kind = kind, Key = key, Title = title };

        static void AddText(HelpDoc doc, HelpPair pair)
        {
            if (pair == null || pair.En.Length == 0) return;
            doc.Texts.Add(pair);
            AddSet(doc.B, pair.En);
            if (pair.Pt.Length > 0 && pair.Pt != pair.En) AddSet(doc.B, pair.Pt);
        }

        static void AddTitle(HelpDoc doc, HelpPair pair) { AddSet(doc.T, pair.En); if (pair.Pt.Length > 0) AddSet(doc.T, pair.Pt); }

        static HelpPair PairOf(object o) => new HelpPair(Json.Text(o, "en"), Json.Text(o, "pt"));

        /// <summary>Builds the index from the cards, the help data (HelpSearch.json) and the Codex (each may be null).</summary>
        public static HelpIndex Build(HowItWorks how, object help, CodexData codex)
        {
            var idx = new HelpIndex();
            var meta = Json.Get(help, "cards");
            if (how != null)
                foreach (var f in how.Cards)
                {
                    var doc = NewDoc("card", f.Key, new HelpPair(f.TitleEn, f.TitlePt));
                    AddTitle(doc, doc.Title);
                    var m = Json.Get(meta, f.Key);
                    if (m is Dictionary<string, object>)
                    {
                        if (Json.Get(m, "level") is double lv) doc.Level = (int)lv;
                        doc.Menu = Json.Text(m, "menu");
                        var words = Json.Get(m, "words");
                        if (words is Dictionary<string, object>) { AddSet(doc.G, Json.Text(words, "en")); AddSet(doc.G, Json.Text(words, "pt")); }
                        if (doc.Menu.Length > 0) AddSet(doc.G, doc.Menu);
                    }
                    foreach (var r in f.Rows)
                    {
                        AddText(doc, new HelpPair(r.En, r.Pt));
                        string rw;
                        if (RowWords.TryGetValue(r.Id, out rw)) AddSet(doc.G, rw);
                        if (r.Id == "drops") { AddSet(doc.D, r.En); AddSet(doc.D, r.Pt); }
                    }
                    idx.Docs.Add(doc);
                    idx.Cards[f.Key] = doc;
                }
            foreach (object u in Json.List(help, "unlocks"))
            {
                string card = Json.Text(u, "card");
                var title = PairOf(Json.Get(u, "title"));
                var why = PairOf(Json.Get(u, "why"));
                int level = Json.Int(u, "level");
                HelpDoc doc;
                if (card.Length > 0 && idx.Cards.TryGetValue(card, out doc))
                {
                    // the unlock entry belongs to a card: its title, menu and lines make that card easier to find
                    AddSet(doc.G, title.En); AddSet(doc.G, title.Pt); AddSet(doc.G, Json.Text(u, "menu"));
                    AddSet(doc.B, why.En); AddSet(doc.B, why.Pt);
                    if (!doc.Level.HasValue || level < doc.Level.Value) doc.Level = level;
                }
                else
                {
                    doc = NewDoc("unlock", Json.Text(u, "key"), title);
                    AddTitle(doc, title);
                    AddSet(doc.G, Json.Text(u, "menu"));
                    doc.Level = level; doc.Menu = Json.Text(u, "menu");
                    AddText(doc, why);
                    idx.Docs.Add(doc);
                }
            }
            if (codex != null)
                foreach (var tab in codex.Tabs)
                    foreach (var e in tab.Entries)
                    {
                        var doc = NewDoc("codex", e.Id, new HelpPair(e.Name, e.Name));
                        doc.Tab = tab.Name;
                        AddSet(doc.T, e.Name);
                        AddSet(doc.G, tab.Name);
                        AddText(doc, new HelpPair(e.Sub, e.Sub));
                        int paragraphs = 0;
                        foreach (var sec in e.Sections)
                            foreach (var p in sec.Paragraphs)
                                if (paragraphs < 4) { AddText(doc, new HelpPair(p, p)); paragraphs++; }
                        idx.Docs.Add(doc);
                    }
            idx.Intro = PairOf(Json.Get(help, "intro"));
            foreach (object s in Json.List(help, "steps"))
            {
                HelpDoc doc;
                if (idx.Cards.TryGetValue(Json.Text(s, "card"), out doc)) idx.Steps.Add(new HelpStep { Doc = doc, Tip = PairOf(s) });
            }
            return idx;
        }

        // ------------------------------------------------------------------------------------ search
        static double Match(HashSet<string> set, string stem)
        {
            if (set.Contains(stem)) return 1;
            if (stem.Length >= 3) foreach (var t in set) if (t.Length > stem.Length && t.StartsWith(stem, StringComparison.Ordinal)) return WPrefix;
            return 0;
        }

        /// <summary>True when the query asks where something comes from (read before the small words go).</summary>
        public static bool IsSource(string query)
        {
            foreach (var w in Words(Fold(query))) if (SourceWords.Contains(w)) return true;
            return false;
        }

        /// <summary>The score of one doc for the query stems.</summary>
        public static double Score(HelpDoc doc, IList<string> words, bool source)
        {
            double total = 0;
            int hits = 0, inTitle = 0;
            foreach (var word in words)
            {
                double best = 0;
                bool titleHit = false;
                foreach (var kv in Expand(word))
                {
                    double sw = kv.Value;
                    double t = Match(doc.T, kv.Key) * WTitle * sw, g = Match(doc.G, kv.Key) * WTag * sw, b = Match(doc.B, kv.Key) * WBody * sw;
                    double d = source ? Match(doc.D, kv.Key) * WSource * sw : 0;
                    if (t > 0 && sw == 1) titleHit = true;
                    best = Math.Max(best, Math.Max(Math.Max(t, g), Math.Max(b, d)));
                }
                if (best > 0) hits++;
                if (titleHit) inTitle++;
                total += best;
            }
            if (total <= 0) return 0;
            double cover = (double)hits / words.Count;
            total *= 0.5 + 0.5 * cover;
            if (inTitle == words.Count) total += WAllInTitle;
            double kind = KindWeight(doc.Kind);
            if (source && doc.Kind == "codex") kind = KindSourceCodex;
            return total * kind;
        }

        static int KindOrder(string kind) => kind == "card" ? 1 : kind == "unlock" ? 2 : kind == "codex" ? 3 : 9;

        /// <summary>The results best first; ties: cards first, then the lower level, then by title. words gets the stems of the query.</summary>
        public static List<HelpResult> Search(HelpIndex index, string query, out List<string> words, int limit = Limit)
        {
            words = Tokens(query);
            var o = new List<HelpResult>();
            if (words.Count == 0 || index == null) return o;
            bool source = IsSource(query);
            foreach (var doc in index.Docs)
            {
                double s = Score(doc, words, source);
                if (s > 0) o.Add(new HelpResult { Doc = doc, Score = s });
            }
            var sorted = o.Select((r, i) => new { r, i }).ToList();
            sorted.Sort((x, y) =>
            {
                if (Math.Abs(x.r.Score - y.r.Score) > 1e-9) return y.r.Score.CompareTo(x.r.Score);
                int ka = KindOrder(x.r.Doc.Kind), kb = KindOrder(y.r.Doc.Kind);
                if (ka != kb) return ka.CompareTo(kb);
                int la = x.r.Doc.Level ?? 0, lb = y.r.Doc.Level ?? 0;
                if (la != lb) return la.CompareTo(lb);
                int c = string.CompareOrdinal(x.r.Doc.Title.En, y.r.Doc.Title.En);
                return c != 0 ? c : x.i.CompareTo(y.i);
            });
            return sorted.Select(x => x.r).Take(limit).ToList();
        }

        // ------------------------------------------------------------------------------------ snippet
        public static string Pick(HelpPair p, string lang) => HowItWorks.IsPt(lang) && p.Pt.Length > 0 ? p.Pt : p.En;

        /// <summary>Cut at a space, at most max characters, with "..." (only at a space).</summary>
        public static string Shorten(string s, int max = Snippet)
        {
            s = string.Join(" ", (s ?? "").Split((char[])null, StringSplitOptions.RemoveEmptyEntries));
            if (s.Length <= max) return s;
            string cut = s.Substring(0, max - 3);
            int at = cut.LastIndexOf(' ');
            if (at > 0) cut = cut.Substring(0, at);
            cut = cut.TrimEnd(' ', ',', ';', ':', '.');
            return cut + "...";
        }

        /// <summary>The text of the doc that holds the most query words, in the language; the first text when none does.</summary>
        public static string SnippetOf(HelpDoc doc, IList<string> words, string lang, int max = Snippet)
        {
            string best = null;
            int bestHits = -1;
            foreach (var pair in doc.Texts)
            {
                string text = Pick(pair, lang);
                var set = new HashSet<string>(Tokens(text));
                int hits = 0;
                foreach (var w in words ?? new string[0])
                    foreach (var stem in Expand(w).Keys) if (set.Contains(stem)) { hits++; break; }
                if (hits > bestHits) { best = text; bestHits = hits; }
            }
            return Shorten(best ?? "", max);
        }

        /// <summary>The Codex tab and entry a result opens, or the card key.</summary>
        public static string Where(HelpDoc d) => d.Kind == "codex" ? d.Tab : d.Menu;
    }
}
