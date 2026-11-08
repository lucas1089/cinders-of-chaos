// Login screen news and character select extras (phase 6, track V; clients client_chaos_login and client_chaos_charselect).
//   * The news panel: what the login screen of the main client shows under the sign-in panel. The data is the website's login services,
//     one GET on <site>/clientservices (server/tools/clientservices.py): the boosted creature and boss, the event schedule and the players online.
//     A panel shows only with data (loginbar.lua): no events, no schedule panel.
//   * The medallions and crests around the sign-in panel (login.lua createDecor), laid out here; drawn procedurally on the Unity side.
//   * The website's account API (chaos_client_api.php, website/README.md "Client API"): one login with the account and password the game login
//     already holds, then `state`: each character's wings, aura and shader, last login and season tag, and the character slots.
// Pure: no engine API, no network. The Unity side makes the requests (ChaosApp.Phase6V.cs).
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    // ============================================================================================================ site addresses
    public static class SiteUrls
    {
        /// <summary>"https://example.com" for a login host (a leading play., login. or game. goes). Null for an empty, local or odd host.</summary>
        public static string Base(string host)
        {
            string u = CharSelectModel.CreateUrl(host);
            const string tail = "/createcharacter.php";
            return u != null && u.EndsWith(tail, StringComparison.Ordinal) ? u.Substring(0, u.Length - tail.Length) : null;
        }

        public static string Services(string host) { string b = Base(host); return b == null ? null : b + "/clientservices"; }
        public static string Account(string host) { string b = Base(host); return b == null ? null : b + "/chaos_client_api.php"; }
    }

    // ============================================================================================================ news
    public sealed class LoginEvent
    {
        public string Name = "", Description = "", ColorLight = "";
        public DateTime Start, End;
        public bool Running(DateTime now) => now >= Start && now <= End;
    }

    public sealed class BoostedMonster
    {
        public string Name = "";
        public Outfit Outfit;
    }

    public sealed class LoginNews
    {
        public int PlayersOnline = -1;
        public BoostedMonster Creature, Boss;
        public readonly List<LoginEvent> Events = new List<LoginEvent>();

        /// <summary>Reads the services answer (the whole object, or one of its parts); a text that is not JSON gives an empty news.</summary>
        public static LoginNews Parse(string json)
        {
            var n = new LoginNews();
            object root = Json.TryParse(json);
            if (!(root is Dictionary<string, object>)) return n;
            object cache = Json.Get(root, "cacheinfo") ?? root;
            if (Json.Get(cache, "playersonline") is double p) n.PlayersOnline = (int)Math.Max(0, p);
            object boosted = Json.Get(root, "boostedcreature") ?? root;
            n.Creature = Monster(Json.Get(boosted, "creature"));
            n.Boss = Monster(Json.Get(boosted, "boss"));
            object sched = Json.Get(root, "eventschedule") ?? root;
            foreach (object e in Json.List(sched, "eventlist"))
            {
                var ev = new LoginEvent { Name = Json.Text(e, "name"), Description = Json.Text(e, "description"), ColorLight = Json.Text(e, "colorlight") };
                if (ev.Name.Length == 0 || !ParseDate(Json.Get(Json.Get(e, "startdate"), "date"), out ev.Start) || !ParseDate(Json.Get(Json.Get(e, "enddate"), "date"), out ev.End)) continue;
                n.Events.Add(ev);
            }
            n.Events.Sort((a, b) => a.Start.CompareTo(b.Start));
            return n;
        }

        static BoostedMonster Monster(object o)
        {
            if (!(o is Dictionary<string, object>)) return null;
            string name = Json.Text(o, "name");
            if (name.Length == 0) return null;
            object of = Json.Get(o, "outfit");
            var outfit = new Outfit(Json.Int(of, "type"), Json.Int(of, "head"), Json.Int(of, "body"), Json.Int(of, "legs"), Json.Int(of, "feet"), Json.Int(of, "addons"));
            outfit.LookTypeEx = Json.Int(of, "auxType");
            return new BoostedMonster { Name = name, Outfit = outfit };
        }

        /// <summary>"2026-11-08 18:00:00" or "2026-11-08": the server's calendar stamps.</summary>
        public static bool ParseDate(object text, out DateTime d)
        {
            d = default(DateTime);
            string s = text as string;
            if (string.IsNullOrEmpty(s)) return false;
            return DateTime.TryParseExact(s, new[] { "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd" }, CultureInfo.InvariantCulture, DateTimeStyles.None, out d);
        }

        /// <summary>The events to list: the ones running now first, then the next to start, at most `max`.</summary>
        public List<LoginEvent> Upcoming(DateTime now, int max = 4)
        {
            var running = new List<LoginEvent>();
            var next = new List<LoginEvent>();
            foreach (var e in Events)
            {
                if (e.Running(now)) running.Add(e);
                else if (e.Start > now) next.Add(e);
            }
            running.AddRange(next);
            if (running.Count > max) running.RemoveRange(max, running.Count - max);
            return running;
        }

        /// <summary>"Now", "in 3 days" or "tomorrow" style words need translation, so the model gives the numbers: days until the start, 0 when it runs now.</summary>
        public static int DaysUntil(LoginEvent e, DateTime now) => e.Running(now) ? 0 : Math.Max(1, (int)Math.Ceiling((e.Start - now).TotalDays));
    }

    /// <summary>Which panels of the news bar show (loginbar.lua): each only with data, the whole bar only on the sign-in panel itself.</summary>
    public static class LoginBar
    {
        public struct State { public bool Bar, Info, Boost; }

        public static State Of(LoginNews n, bool loginPanel, bool splash, bool noRoom, bool charList, bool inGame)
        {
            bool screen = loginPanel && !splash && !noRoom && !charList && !inGame;
            bool info = n != null && n.Events.Count > 0;
            bool boost = n != null && (n.Creature != null || n.Boss != null);
            return new State { Bar = screen && (info || boost), Info = info, Boost = boost };
        }

        /// <summary>The x of each shown panel, centred in `width` with `gap` between: widths of the panels in order, false for a hidden one (x = -1).</summary>
        public static float[] Row(float[] widths, bool[] shown, float width, float gap = 8)
        {
            var xs = new float[widths.Length];
            float total = 0;
            int count = 0;
            for (int i = 0; i < widths.Length; i++) if (shown[i]) { total += widths[i]; count++; }
            total += Math.Max(0, count - 1) * gap;
            float x = (float)Math.Floor((width - total) / 2);
            for (int i = 0; i < widths.Length; i++)
            {
                if (!shown[i]) { xs[i] = -1; continue; }
                xs[i] = x;
                x += widths[i] + gap;
            }
            return xs;
        }
    }

    /// <summary>The medallions (64 x 64) left and right of the sign-in panel and the crests (96 x 22) on its top and bottom edge, as login.lua anchors them.</summary>
    public static class LoginDecor
    {
        public const float Medallion = 64, CrestW = 96, CrestH = 22;

        /// <summary>The left medallion's rect for a panel: centred on its left edge, 46 px under its top (a phone: fully outside the fields).</summary>
        public static void Medallions(float px, float py, float pw, bool phone, out float lx, out float ly, out float rx, out float ry)
        {
            ly = ry = py + 46 - Medallion / 2;
            lx = px - Medallion / 2 + (phone ? -12 : 0);
            rx = px + pw - Medallion / 2 + (phone ? 12 : 0);
        }

        public static void Crests(float px, float py, float pw, float ph, out float x, out float topY, out float bottomY)
        {
            x = px + pw / 2 - CrestW / 2;
            topY = py - 6;
            bottomY = py + ph - CrestH + 6;
        }
    }

    // ============================================================================================================ account API
    public sealed class AccountLook
    {
        public string Name = "", Season = "";
        public Outfit Outfit;
        public int Level, Vocation;
        public long LastLogin;
    }

    public sealed class AccountAnswer
    {
        public bool Ok;
        public string Token = "", Error = "";
        public int ExpiresIn = 1500, SlotsUsed = -1, SlotsLimit = -1;
        /// <summary>The create window's part of the state (classes, season, name rules, Terms): Phase7XCharacter.cs. Null when the answer had no account block.</summary>
        public CreateState Create;
        public readonly Dictionary<string, AccountLook> Looks = new Dictionary<string, AccountLook>();
    }

    public static class AccountApi
    {
        public static string LoginRequest(string account, string password, string nonce) =>
            Json.Serialize(new Dictionary<string, object> { { "action", "login" }, { "account", account }, { "password", password }, { "nonce", nonce } });

        public static string StateRequest(string token) => Json.Serialize(new Dictionary<string, object> { { "action", "state" }, { "token", token } });
        public static string LogoutRequest(string token) => Json.Serialize(new Dictionary<string, object> { { "action", "logout" }, { "token", token } });

        /// <summary>A random 32 digit hex nonce: the website refuses one it has seen. `next` gives 0-15.</summary>
        public static string Nonce(Func<int> next)
        {
            var c = new char[32];
            for (int i = 0; i < 32; i++) c[i] = "0123456789abcdef"[next() & 15];
            return new string(c);
        }

        /// <summary>The answer of login or state. A body that is not JSON or says ok:false gives Ok = false with the website's message.</summary>
        public static AccountAnswer Parse(string body)
        {
            var a = new AccountAnswer();
            object root = Json.TryParse(body);
            if (!(root is Dictionary<string, object>)) { a.Error = "no answer"; return a; }
            a.Ok = Json.Truthy(root, "ok");
            if (!a.Ok)
            {
                a.Error = Json.Text(root, "message");
                var errs = Json.List(root, "errors");
                if (a.Error.Length == 0 && errs.Count > 0 && errs[0] is string first) a.Error = first;
                if (a.Error.Length == 0) a.Error = Json.Text(root, "error");
                return a;
            }
            a.Token = Json.Text(root, "token");
            a.ExpiresIn = Math.Max(60, Json.Int(root, "expiresIn", 1500));
            object slots = Json.Get(Json.Get(root, "account"), "slots");
            if (slots != null) { a.SlotsUsed = Json.Int(slots, "used", -1); a.SlotsLimit = Json.Int(slots, "limit", -1); }
            a.Create = CreateState.From(Json.Get(root, "account"));
            if (Json.Get(root, "looks") is Dictionary<string, object> looks)
                foreach (var kv in looks)
                {
                    object l = kv.Value;
                    var o = new Outfit(Json.Int(l, "type"), Json.Int(l, "head"), Json.Int(l, "body"), Json.Int(l, "legs"), Json.Int(l, "feet"), Json.Int(l, "addons"))
                    { Wings = Json.Int(l, "wings"), Aura = Json.Int(l, "aura"), Shader = Json.Text(l, "shader") };
                    a.Looks[kv.Key] = new AccountLook
                    {
                        Name = kv.Key, Outfit = o, Level = Json.Int(l, "level"), Vocation = Json.Int(l, "vocation"),
                        LastLogin = (long)Json.Number(l, "lastLogin"), Season = Json.Text(l, "season"),
                    };
                }
            return a;
        }
    }

    // ============================================================================================================ card text
    public static class CharCardText
    {
        /// <summary>The login list's outfit, with the website's wings, aura and shader added; the list's own look wins where it has one.</summary>
        public static Outfit Merge(Outfit list, AccountLook look)
        {
            Outfit src = list != null && list.LookType != 0 ? list : look?.Outfit;
            if (src == null || src.LookType == 0) return list;
            var o = new Outfit(src.LookType, src.Head, src.Body, src.Legs, src.Feet, src.Addons, src.Mount) { LookTypeEx = src.LookTypeEx };
            if (look?.Outfit != null) { o.Wings = look.Outfit.Wings; o.Aura = look.Outfit.Aura; o.Shader = look.Outfit.Shader ?? ""; }
            return o;
        }

        /// <summary>The last login in words (key = the English text, with {0} for a number); the caller translates it. Returns the key and the number.</summary>
        public static string LastLoginKey(long ts, long now, out int n, bool shortForm = false)
        {
            n = 0;
            if (ts <= 0) return shortForm ? "never played" : "Never played";
            long d = Math.Max(0, now - ts);
            if (d < 120) return shortForm ? "just now" : "Last played just now";
            if (d < 3600) { n = (int)(d / 60); return shortForm ? "{0} minutes ago" : "Last played {0} minutes ago"; }
            if (d < 7200) return shortForm ? "an hour ago" : "Last played an hour ago";
            if (d < 86400) { n = (int)(d / 3600); return shortForm ? "{0} hours ago" : "Last played {0} hours ago"; }
            if (d < 172800) return shortForm ? "yesterday" : "Last played yesterday";
            if (d < 30 * 86400) { n = (int)(d / 86400); return shortForm ? "{0} days ago" : "Last played {0} days ago"; }
            n = -1;   // a date: the caller adds it
            return shortForm ? "{0}" : "Last played on {0}";
        }

        public static string DateOf(long ts) => DateTimeOffset.FromUnixTimeSeconds(Math.Max(0, ts)).UtcDateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

        /// <summary>"3 of 5 slots used" numbers: never more used than the limit says; 'full' when no slot is free.</summary>
        public static bool SlotsFull(int used, int limit) => limit >= 0 && used >= limit;
    }
}
