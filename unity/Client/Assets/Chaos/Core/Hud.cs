// HUD models (phase 3, track H): toasts, buff bar, cast bar, energy shield, monk chi, tiered monster bar, anti-bot check and
// report, and the options the server wants to know (keep attacking while moving, right-click equips, display scale,
// language). Pure logic: every rule comes from the main client's *math / *logic modules (game_chaosnotify notifyview.lua,
// game_buffbar buffmath.lua, game_castbar castbarmath.lua, game_energyshield shieldmath.lua, game_monkchi chimath.lua,
// game_monsterbar monsterbar*.lua, game_antibot antibot_logic.lua, game_kitewalk, game_rightclickequip, game_chaosscale,
// client_chaos_locale). Times are session milliseconds (GameSession.Now). The Unity side only draws these.
//
//   opcode  module            wire
//   79      notify            server -> client JSON {action = kind, message ...}; client -> server on 151 / 152 (plain text) for the buttons
//   125     monsterbar        client query {cid}; server info {cid, tier, label, role, level, mods}; server mech {cid, boss, label, ms, kind}
//   157     scale + locale    client hello {lang}; server scale {level, f}
//   186     kitewalk          client {on}
//   188     rightclickequip   client {on}; server multiuse {ids}
//   211     antibot           server check / checkResult / reportOpen / reportResult; client answer / another / reportOpen / report
//   224     energyshield      server text "es:cur:max"; client text "hello"
//   231     castbar           server start / end / other / otherEnd; client cancel
//   234     buffbar           client sync; server full / diff
//   247     monkchi           server text "chi:chi:max:decay"
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    public static class HudOp
    {
        public const byte Notify = 79, MonsterBar = 125, Scale = 157, KiteWalk = 186, RightClickEquip = 188, Antibot = 211,
                          EnergyShield = 224, CastBar = 231, BuffBar = 234, MonkChi = 247,
                          /// <summary>Party invitation answers and the catacomb start / queue, plain text (the toast buttons).</summary>
                          CatacombCommand = 151, CatacombQueue = 152;
    }

    // ============================================================================================================== toasts
    public sealed class ToastStyle
    {
        public string Title, TitleColor, BorderColor;
        public int DurationMs;
        public ToastStyle(string title, string color, string border, int ms) { Title = title; TitleColor = color; BorderColor = border; DurationMs = ms; }
    }

    public sealed class Toast
    {
        public string Type = "", Message = "";
        public ToastStyle Style;
        public double StartAt = -1;
        /// <summary>Session ms a press on the toast paused its timer at (phase 8 track A, ToastPause); -1 when running.</summary>
        public double PausedAt = -1;
        public int MonsterLook;
        /// <summary>Party invitation: the inviter. Catacomb free: element and level.</summary>
        public string Inviter = "", Element = "";
        public int Level;
        public bool HasButtons => ToastKinds.HasButtons(Type);
        public double EndAt => StartAt + Style.DurationMs;
        public double Left(double now) => Math.Max(0, EndAt - now);
        /// <summary>Share of the time left, 0..1 (the timer bar).</summary>
        public double Fraction(double now) => Style.DurationMs <= 0 ? 0 : Math.Min(1, Left(now) / Style.DurationMs);
    }

    public static class ToastKinds
    {
        const string Tan = "#a3844b", Brown = "#6a5632";

        public static readonly Dictionary<string, ToastStyle> Styles = new Dictionary<string, ToastStyle>
        {
            { "GM_BROADCAST", new ToastStyle("GAMEMASTER NOTIFICATION", Tan, Brown, 30000) },
            { "TASK_COMPLETE", new ToastStyle("TASK COMPLETED", Tan, Brown, 10000) },
            { "BATTLE_PASS", new ToastStyle("BATTLE PASS REWARD", Tan, Brown, 10000) },
            { "PARTY_INVITE", new ToastStyle("PARTY INVITATION", Tan, Brown, 30000) },
            { "BOUNTY", new ToastStyle("BOUNTY BOARD", Tan, Brown, 8000) },
            { "NEW_PLAYER", new ToastStyle("NEW ADVENTURER", Tan, Brown, 12000) },
            { "BESTIARY", new ToastStyle("BESTIARY", "#b08a4a", Brown, 7000) },
            { "ACHIEVEMENT", new ToastStyle("ACHIEVEMENT UNLOCKED", "#5cc8c0", "#2c6e69", 8000) },
            { "ASCENSION", new ToastStyle("ASCENSION", "#c9a24a", Brown, 10000) },
            { "MARKET", new ToastStyle("MARKET", "#e8b84a", Brown, 9000) },
            { "SALE", new ToastStyle("ITEM SOLD", "#e8b84a", Brown, 12000) },
            { "INVASION", new ToastStyle("INVASION", "#d8452a", "#7a1a12", 9000) },
            { "CURSED_CHEST", new ToastStyle("CURSED CHEST", "#b46ae0", "#4a1a6a", 9000) },
            { "WEEKLY_CHEST", new ToastStyle("WEEKLY CHEST", "#e0b24a", "#6a4a1a", 9000) },
            { "MILESTONE", new ToastStyle("LEVEL MILESTONE", "#e8c15a", "#6a4a1a", 10000) },
            { "SEASON_PASS", new ToastStyle("SEASON PASS", "#ff9a3c", "#7a3a12", 9000) },
            { "PACT", new ToastStyle("CHAOS PACT", "#e07a4a", "#7a3a12", 12000) },
            { "JOURNEY", new ToastStyle("SEASONAL JOURNEY", "#ff9a3c", "#7a3a12", 8000) },
            { "BOSS_POINT", new ToastStyle("BOSS PASSIVE POINT", "#d8a03a", "#7a5410", 10000) },
            { "SCREENSHOT", new ToastStyle("SCREENSHOT", "#d8c08a", Brown, 5000) },
            { "CATACOMB_FREE", new ToastStyle("CATACOMB AVAILABLE", Tan, Brown, 30000) },
        };

        /// <summary>Message kinds ({"action": kind, "message": text}) to a toast type (notifyview.lua MESSAGE_TYPES).</summary>
        public static readonly Dictionary<string, string> MessageTypes = new Dictionary<string, string>
        {
            { "bounty", "BOUNTY" }, { "newplayer", "NEW_PLAYER" }, { "bestiary", "BESTIARY" }, { "achievement", "ACHIEVEMENT" },
            { "bosspoints", "BOSS_POINT" }, { "ascension", "ASCENSION" }, { "market", "MARKET" }, { "sale", "SALE" },
            { "seasonpass", "SEASON_PASS" }, { "pact", "PACT" }, { "journey", "JOURNEY" }, { "invasion", "INVASION" },
            { "cursedchest", "CURSED_CHEST" }, { "weeklychest", "WEEKLY_CHEST" }, { "milestone", "MILESTONE" },
            { "gmBroadcast", "GM_BROADCAST" },
        };

        public const int Height = 110, ButtonHeight = 140, Gap = 8, TextTop = 28, TextBottom = 18, ButtonTextBottom = 77, MaxHeight = 260, QueueMax = 12, MaxActive = 3;
        public const int DangerMs = 7000;

        public static bool HasButtons(string type) => type == "PARTY_INVITE" || type == "CATACOMB_FREE";
        public static int HeightOf(string type) => HasButtons(type) ? ButtonHeight : Height;

        /// <summary>Toast height for a wrapped text of textHeight pixels, and whether the text had to be cut (notifyview.lua heightFor).</summary>
        public static int HeightFor(string type, double textHeight, out bool cut)
        {
            int bottom = HasButtons(type) ? ButtonTextBottom : TextBottom;
            int needed = TextTop + Math.Max(0, (int)Math.Ceiling(textHeight)) + bottom;
            int h = Math.Min(MaxHeight, Math.Max(HeightOf(type), needed));
            cut = needed > MaxHeight;
            return h;
        }

        /// <summary>Top of each toast, in order, every one below the previous by its own height plus the gap (the stack of notifyview.lua).</summary>
        public static float[] Stack(IList<int> heights, float baseY = 0, int gap = Gap)
        {
            var ys = new float[heights.Count];
            float y = baseY;
            for (int i = 0; i < heights.Count; i++) { ys[i] = y; y += heights[i] + gap; }
            return ys;
        }
    }

    /// <summary>The toasts of opcode 79: three shown at once, the rest in a queue of twelve, a danger line for hunt warnings.</summary>
    public sealed class ToastCenter
    {
        public readonly List<Toast> Queue = new List<Toast>();
        public readonly List<Toast> Active = new List<Toast>();
        public string DangerText = "";
        public bool DangerCaution;
        public double DangerUntil = -1;
        public Func<double> Clock = () => 0;
        /// <summary>On a phone only the toasts that wait for an answer are shown (set by the app).</summary>
        public static bool Phone;
        readonly ExtOpcodes ext;

        public ToastCenter(ExtOpcodes e)
        {
            ext = e;
            if (e != null) e.On(HudOp.Notify, Receive);
        }

        public bool DangerShown(double now) => DangerUntil > now && DangerText.Length > 0;

        public void Receive(ExtMessage m)
        {
            string action = m.Action;
            object d = m.Root;   // the toast payloads keep their fields next to "action", not under "data"
            string message = Json.Text(d, "message");
            ToastKinds.MessageTypes.TryGetValue(action, out string type);
            if (type != null)
            {
                if (message.Length > 0) Add(type, message, (int)Json.Number(d, "monsterLookType"));
                return;
            }
            switch (action)
            {
                case "taskComplete":
                    if (Json.Get(d, "taskName") != null && Json.Get(d, "taskPoints") != null && Json.Get(d, "killCount") != null)
                        Add("TASK_COMPLETE", Loc.T("Task Complete: of {0}, killed {1} and received {2} task points", Json.Text(d, "taskName"), Json.Int(d, "killCount"), Json.Int(d, "taskPoints")), (int)Json.Number(d, "monsterLookType"));
                    break;
                case "battlePassComplete":
                    if (Json.Get(d, "missionName") != null && Json.Get(d, "expPoints") != null)
                        Add("BATTLE_PASS", Loc.T("Mission Complete: {0} and received {1} battle pass exp", Json.Text(d, "missionName"), Json.Int(d, "expPoints")), (int)Json.Number(d, "monsterLookType"));
                    break;
                case "danger":
                    ShowDanger(message, Json.Truthy(d, "caution"), Clock());
                    break;
                case "partyInvite":
                    if (Json.Get(d, "inviterName") != null)
                    {
                        string element = Capital(Json.Text(d, "element", "unknown"));
                        var t = Add("PARTY_INVITE", Loc.T("{0} [{1}] invited you to join a party for catacomb {2} level {3}!", Json.Text(d, "inviterName"), Json.Int(d, "inviterResets"), element, Json.Int(d, "level")), 0);
                        t.Inviter = Json.Text(d, "inviterName");
                        t.Level = Json.Int(d, "level");
                        t.Element = Json.Text(d, "element");
                    }
                    break;
                case "catacombFree":
                    if (Json.Get(d, "element") != null && Json.Get(d, "level") != null)
                    {
                        string el = Json.Text(d, "element");
                        string lvl = Json.Get(d, "level") is string s ? s : Json.Int(d, "level").ToString(CultureInfo.InvariantCulture);
                        var t = Add("CATACOMB_FREE", Loc.T("The {0} Catacomb Level {1} is now free!", Capital(el), lvl), 0);
                        t.Element = el;
                        t.Level = Json.Int(d, "level");
                    }
                    break;
            }
        }

        static string Capital(string s) => s.Length == 0 ? s : char.ToUpperInvariant(s[0]) + s.Substring(1);

        public Toast Add(string type, string message, int monsterLook = 0)
        {
            if (!ToastKinds.Styles.TryGetValue(type, out var style)) return null;
            if (!ToastPause.Shown(type, Phone)) return null;   // a phone shows only the invitations (game_chaosnotify O401)
            var t = new Toast { Type = type, Style = style, Message = message, MonsterLook = monsterLook };
            Enqueue(Queue, t, ToastKinds.QueueMax);
            Tick(Clock());
            return t;
        }

        /// <summary>At most `max` wait; when it is full the oldest toast without buttons gives way (an invitation is kept). Returns the one dropped.</summary>
        public static Toast Enqueue(List<Toast> queue, Toast item, int max)
        {
            queue.Add(item);
            if (queue.Count <= max) return null;
            int drop = 0;
            for (int i = 0; i < queue.Count; i++) if (!queue[i].HasButtons) { drop = i; break; }
            var gone = queue[drop];
            queue.RemoveAt(drop);
            return gone;
        }

        public void ShowDanger(string text, bool caution, double now)
        {
            DangerText = text ?? "";
            DangerCaution = caution;
            DangerUntil = now + ToastKinds.DangerMs;
        }

        /// <summary>Drops toasts whose time ran out and takes waiting ones into the free places.</summary>
        public void Tick(double now)
        {
            Active.RemoveAll(t => t.PausedAt < 0 && now >= t.EndAt);
            while (Active.Count < ToastKinds.MaxActive && Queue.Count > 0)
            {
                var t = Queue[0];
                Queue.RemoveAt(0);
                t.StartAt = now;
                Active.Add(t);
            }
        }

        public void Close(Toast t) { Active.Remove(t); Tick(Clock()); }

        // the buttons
        public void Accept(Toast t)
        {
            if (t.Type == "PARTY_INVITE") ext?.SendText(HudOp.CatacombCommand, "accept_invite|" + t.Inviter);
            else if (t.Type == "CATACOMB_FREE") ext?.SendText(HudOp.CatacombCommand, "start_catacomb|solo|" + t.Level + "|" + t.Element);
            Close(t);
        }

        public void Decline(Toast t)
        {
            if (t.Type == "PARTY_INVITE") ext?.SendText(HudOp.CatacombCommand, "decline_invite|" + t.Inviter);
            else if (t.Type == "CATACOMB_FREE") ext?.SendText(HudOp.CatacombQueue, "leave_queue");
            Close(t);
        }

        public void Clear() { Queue.Clear(); Active.Clear(); DangerText = ""; DangerUntil = -1; }
    }

    // ============================================================================================================== buff bar
    public sealed class BuffEntry
    {
        public string Key = "", Name = "", Desc = "", Icon = "";
        public bool Debuff;
        /// <summary>Session ms when the buff ends; -1 for no time limit.</summary>
        public double EndAt = -1;
        /// <summary>Stacks; -1 none.</summary>
        public double Stacks = -1;
        public int Seq;
        public double Remaining(double now) => EndAt < 0 ? -1 : Math.Max(0, (EndAt - now) / 1000.0);
    }

    /// <summary>Buff and debuff icons (opcode 234): the server sends `full {list}` and `diff {add, upd, del}`; times are counted down here.</summary>
    public sealed class BuffBar
    {
        public const double GraceMs = 1500;
        public readonly Dictionary<string, BuffEntry> Buffs = new Dictionary<string, BuffEntry>();
        public bool Synced, Shown = true, Timers = true;
        int seq;
        public Func<double> Clock = () => 0;
        readonly ExtOpcodes ext;

        public BuffBar(ExtOpcodes e)
        {
            ext = e;
            if (e != null) e.On(HudOp.BuffBar, m => Apply(m.Action, m.Data, Clock()));
        }

        /// <summary>Asks the server for the whole list (the main client does it when it starts watching).</summary>
        public void Sync() { if (Shown) ext?.Send(HudOp.BuffBar, "sync", new Dictionary<string, object>()); }

        BuffEntry Entry(object e, double now, int seqNo)
        {
            string key = Json.Text(e, "k");
            if (key.Length == 0) return null;
            var b = new BuffEntry { Key = key, Name = Json.Text(e, "n", key), Desc = Json.Text(e, "d"), Icon = Json.Text(e, "i"), Debuff = Json.Int(e, "t") == 1, Seq = seqNo };
            if (Json.Get(e, "l") is double l) b.EndAt = now + Math.Max(0, l);
            if (Json.Get(e, "s") is double s) b.Stacks = s;
            return b;
        }

        void Put(object e, double now)
        {
            BuffEntry old;
            Buffs.TryGetValue(Json.Text(e, "k"), out old);
            seq++;
            var entry = Entry(e, now, old != null ? old.Seq : seq);
            if (entry != null) Buffs[entry.Key] = entry;
        }

        public bool Apply(string action, object data, double now)
        {
            if (action == "full")
            {
                Buffs.Clear();
                seq = 0;
                Synced = true;
                foreach (var e in Json.List(data, "list")) Put(e, now);
                return true;
            }
            if (action != "diff") return false;
            bool changed = false;
            foreach (var e in Json.List(data, "add")) { Put(e, now); changed = true; }
            foreach (var u in Json.List(data, "upd"))
            {
                if (!Buffs.TryGetValue(Json.Text(u, "k"), out var b)) continue;
                b.EndAt = Json.Get(u, "l") is double l ? now + Math.Max(0, l) : -1;
                b.Stacks = Json.Get(u, "s") is double s ? s : -1;
                changed = true;
            }
            foreach (var k in Json.List(data, "del")) if (k is string ks && Buffs.Remove(ks)) changed = true;
            return changed;
        }

        public void Clear() { Buffs.Clear(); seq = 0; Synced = false; }

        public static bool Expired(BuffEntry e, double now) => e.EndAt >= 0 && now > e.EndAt + GraceMs;

        /// <summary>Drops buffs whose time is long over (a lost `del`); returns how many went.</summary>
        public int Prune(double now)
        {
            var gone = new List<string>();
            foreach (var kv in Buffs) if (Expired(kv.Value, now)) gone.Add(kv.Key);
            foreach (var k in gone) Buffs.Remove(k);
            return gone.Count;
        }

        /// <summary>Buffs first, then debuffs, each in the order the server listed them. nBuffs says where the debuffs start.</summary>
        public List<BuffEntry> Ordered(out int nBuffs)
        {
            var buffs = new List<BuffEntry>();
            var debuffs = new List<BuffEntry>();
            foreach (var e in Buffs.Values) (e.Debuff ? debuffs : buffs).Add(e);
            Comparison<BuffEntry> bySeq = (a, b) => a.Seq != b.Seq ? a.Seq.CompareTo(b.Seq) : string.CompareOrdinal(a.Key, b.Key);
            buffs.Sort(bySeq);
            debuffs.Sort(bySeq);
            nBuffs = buffs.Count;
            buffs.AddRange(debuffs);
            return buffs;
        }

        /// <summary>The buffs up now, lower-case names (debuffs and ended ones left out); null while the server has not sent its list.</summary>
        public HashSet<string> ActiveNames(double now)
        {
            if (!Synced) return null;
            var set = new HashSet<string>();
            foreach (var e in Buffs.Values) if (!e.Debuff && !(e.EndAt >= 0 && now > e.EndAt)) set.Add(e.Name.ToLowerInvariant());
            return set;
        }

        /// <summary>Compact time: 45s, 1:05, 12m, 2h, 3d.</summary>
        public static string Format(double sec)
        {
            if (sec < 0) return "";
            long s = (long)Math.Max(0, Math.Ceiling(sec - 1e-9));
            if (s < 60) return s + "s";
            if (s < 600) return (s / 60) + ":" + (s % 60).ToString("00", CultureInfo.InvariantCulture);
            if (s < 3600) return (s / 60) + "m";
            long h = s / 3600;
            return h >= 24 ? (h / 24) + "d" : h + "h";
        }

        /// <summary>Longer text for the tooltip: 1h 05m 09s, 5m 03s, 45s.</summary>
        public static string FormatLong(double sec)
        {
            long s = (long)Math.Max(0, Math.Ceiling(sec - 1e-9));
            long h = s / 3600, m = s % 3600 / 60, r = s % 60;
            if (h > 0) return h + "h " + m.ToString("00", CultureInfo.InvariantCulture) + "m " + r.ToString("00", CultureInfo.InvariantCulture) + "s";
            if (m > 0) return m + "m " + r.ToString("00", CultureInfo.InvariantCulture) + "s";
            return r + "s";
        }

        /// <summary>Tooltip lines: name, the description while Alt is held (else a hint), stacks and the time left.</summary>
        public static string Tooltip(BuffEntry e, double now, bool alt)
        {
            var lines = new List<string> { e.Name + (e.Debuff ? Loc.T("  (debuff)") : "") };
            if (alt && e.Desc.Length > 0) lines.Add(e.Desc);
            if (e.Stacks > 0) lines.Add(Loc.T("Stacks: {0}", (int)e.Stacks));
            double left = e.Remaining(now);
            lines.Add(left >= 0 ? Loc.T("Time left: {0}", FormatLong(left)) : Loc.T("No time limit"));
            if (!alt && e.Desc.Length > 0) lines.Add(Loc.T("Hold Alt for what it does."));
            return string.Join("\n", lines);
        }

        /// <summary>A short label for a coloured square (no icon art in Unity): the initials of two words, else three letters.</summary>
        public static string Label(BuffEntry e)
        {
            var words = (e.Name.Length > 0 ? e.Name : e.Key).Split(new[] { ' ', '_', '-' }, StringSplitOptions.RemoveEmptyEntries);
            if (words.Length == 0) return "?";
            if (words.Length >= 2) return (words[0].Substring(0, 1) + words[1].Substring(0, 1)).ToUpperInvariant();
            return words[0].Substring(0, Math.Min(3, words[0].Length)).ToUpperInvariant();
        }

        /// <summary>The square's colour as r, g, b 0..1: reds for a debuff, a stable hue per key for a buff.</summary>
        public static float[] Colour(BuffEntry e)
        {
            uint h = 2166136261;
            foreach (char c in e.Key) { h ^= c; h *= 16777619; }
            if (e.Debuff) return new[] { 0.55f + (h & 0xF) / 100f, 0.12f + ((h >> 4) & 0x7) / 100f, 0.12f };
            float hue = (h % 360) / 360f;
            return Hsv(hue, 0.55f, 0.6f);
        }

        static float[] Hsv(float h, float s, float v)
        {
            float r = v, g = v, b = v;
            float c = v * s, hh = h * 6f, x = c * (1 - Math.Abs(hh % 2f - 1)), m = v - c;
            switch ((int)hh % 6)
            {
                case 0: r = c; g = x; b = 0; break;
                case 1: r = x; g = c; b = 0; break;
                case 2: r = 0; g = c; b = x; break;
                case 3: r = 0; g = x; b = c; break;
                case 4: r = x; g = 0; b = c; break;
                default: r = c; g = 0; b = x; break;
            }
            return new[] { r + m, g + m, b + m };
        }

        /// <summary>Icon cells flowing left to right, a new row when one is full (buffmath.lua flow): x, y and the bar height.</summary>
        public static List<(int x, int y)> Flow(int count, int rowWidth, int size, int gap, out int height) =>
            Flow(count, rowWidth, size, size, gap, out height);

        /// <summary>Same with cells of their own width and height (a short name over a timer needs more than a square).</summary>
        public static List<(int x, int y)> Flow(int count, int rowWidth, int cellW, int cellH, int gap, out int height)
        {
            int per = Math.Max(1, (rowWidth + gap) / (cellW + gap));
            var cells = new List<(int, int)>();
            for (int i = 0; i < count; i++) cells.Add(((i % per) * (cellW + gap), (i / per) * (cellH + gap)));
            int rows = (count + per - 1) / per;
            height = rows > 0 ? rows * (cellH + gap) - gap : 0;
            return cells;
        }
    }

    // ============================================================================================================== cast bar
    public sealed class CastEntry
    {
        public string Name = "";
        public double Start, Ms, EndAt = -1;
        public int Serial;
        public string Result = "";
        public bool Portal;
    }

    /// <summary>Cast time spells (opcode 231): your own bar, and bars over other casters.</summary>
    public sealed class CastBar
    {
        public static readonly Dictionary<string, string> ResultText = new Dictionary<string, string>
        {
            { "moved", "Interrupted: moved" }, { "paralysed", "Interrupted: paralysed" }, { "died", "Interrupted" }, { "logout", "Interrupted" },
            { "spell", "Interrupted: new spell" }, { "portal", "Interrupted: portal" }, { "cancel", "Cancelled" },
            { "failed", "Failed" }, { "hit", "Interrupted: hit" }, { "refused", "Refused" },
        };
        public const double MaxMs = 60000, LostEndMs = 4000, ShowResultMs = 900;

        public CastEntry Mine;
        public readonly Dictionary<uint, CastEntry> Others = new Dictionary<uint, CastEntry>();
        public Func<double> Clock = () => 0;
        readonly ExtOpcodes ext;

        public CastBar(ExtOpcodes e)
        {
            ext = e;
            if (e != null) e.On(HudOp.CastBar, m => Receive(m.Action, m.Data, Clock()));
        }

        /// <summary>0..1 of a cast that started at startMs and lasts ms.</summary>
        public static double Progress(double startMs, double ms, double nowMs)
        {
            if (ms <= 0) return 1;
            return Math.Max(0, Math.Min(1, (nowMs - startMs) / ms));
        }

        /// <summary>"Doomtide  0.8s".</summary>
        public static string Label(string name, double ms, double elapsed) =>
            name + "  " + (Math.Max(0, ms - elapsed) / 1000).ToString("0.0", CultureInfo.InvariantCulture) + "s";

        public static string ResultLabel(string result) =>
            result == "done" ? null : Loc.T(ResultText.TryGetValue(result ?? "", out var t) ? t : "Interrupted");

        public void Receive(string action, object d, double now)
        {
            switch (action)
            {
                case "start":
                {
                    double ms = Json.Number(d, "ms");
                    if (ms <= 0) return;
                    Mine = new CastEntry { Name = Json.Text(d, "n"), Ms = Math.Min(ms, MaxMs), Start = now, Serial = Json.Int(d, "s") };
                    break;
                }
                case "end":
                    EndMine(Json.Text(d, "r", "done"), Json.Int(d, "s"), now);
                    break;
                case "other":
                {
                    double ms = Json.Number(d, "ms");
                    if (Json.Get(d, "c") == null || ms <= 0) return;
                    Others[(uint)Json.Number(d, "c")] = new CastEntry { Name = Json.Text(d, "n"), Ms = Math.Min(ms, MaxMs), Start = now };
                    break;
                }
                case "otherEnd":
                {
                    if (Json.Get(d, "c") == null) return;
                    if (Others.TryGetValue((uint)Json.Number(d, "c"), out var o))
                    {
                        string r = Json.Text(d, "r", "done");
                        o.Result = r;
                        o.EndAt = now + (r == "done" ? 200 : 600);
                    }
                    break;
                }
            }
        }

        public void EndMine(string result, int serial, double now)
        {
            if (Mine == null || Mine.EndAt >= 0 || (serial != 0 && Mine.Serial != 0 && serial != Mine.Serial)) return;
            Mine.Result = result;
            Mine.EndAt = now + (result == "done" ? 250 : ShowResultMs);
        }

        /// <summary>The cast is running (not ended).</summary>
        public bool Casting => Mine != null && Mine.EndAt < 0;

        /// <summary>Drops finished bars; a cast whose end never came is closed as done.</summary>
        public void Tick(double now)
        {
            if (Mine != null)
            {
                if (Mine.EndAt < 0 && now - Mine.Start > Mine.Ms + LostEndMs) EndMine("done", 0, now);
                if (Mine.EndAt >= 0 && now >= Mine.EndAt) Mine = null;
            }
            var gone = new List<uint>();
            foreach (var kv in Others)
                if ((kv.Value.EndAt >= 0 && now >= kv.Value.EndAt) || now - kv.Value.Start > kv.Value.Ms + 3000) gone.Add(kv.Key);
            foreach (var k in gone) Others.Remove(k);
        }

        /// <summary>Click on your bar while it casts: cancel the spell.</summary>
        public bool Cancel()
        {
            if (!Casting) return false;
            ext?.Send(HudOp.CastBar, "cancel");
            return true;
        }

        public void Clear() { Mine = null; Others.Clear(); }

        /// <summary>Text of your bar: the time left while casting, the name when done, the reason when interrupted.</summary>
        public string MineText(double now)
        {
            if (Mine == null) return "";
            if (Mine.EndAt < 0) return Label(Mine.Name, Mine.Ms, now - Mine.Start);
            return Mine.Result == "done" ? Mine.Name : ResultLabel(Mine.Result);
        }

        /// <summary>Colour class of a bar: casting, done, interrupted.</summary>
        public static string State(CastEntry c) => c.EndAt < 0 ? "casting" : c.Result == "done" ? "done" : "interrupted";
    }

    // ============================================================================================================== energy shield, chi
    /// <summary>The energy shield (opcode 224): plain text "es:cur:max", eased on screen; "hello" asks for the current value after the login.</summary>
    public sealed class EnergyShield
    {
        public const double EaseMs = 900;
        public int Current, Max;
        public double Shown;
        double easeFrom, easeStart = -1;
        readonly ExtOpcodes ext;

        public EnergyShield(ExtOpcodes e)
        {
            ext = e;
            if (e != null) e.OnText(HudOp.EnergyShield, wire => Receive(wire, 0));
        }

        public Func<double> Clock = () => 0;

        public static bool Parse(string text, out int cur, out int max)
        {
            cur = max = 0;
            if (text == null || !text.StartsWith("es:", StringComparison.Ordinal)) return false;
            var p = text.Split(':');
            if (p.Length != 3 || !int.TryParse(p[1], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out cur) ||
                !int.TryParse(p[2], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out max)) return false;
            if (max < 0) max = 0;
            if (cur < 0) cur = 0;
            if (cur > max) cur = max;
            return true;
        }

        public bool Receive(string text, double now)
        {
            if (!Parse(text, out int cur, out int max)) return false;
            if (ext != null && now == 0) now = Clock();
            easeFrom = Shown;
            easeStart = now;
            Current = cur;
            Max = max;
            if (max <= 0) { Shown = 0; easeStart = -1; }
            return true;
        }

        public void Hello() { ext?.SendText(HudOp.EnergyShield, "hello"); }

        /// <summary>The value drawn at `now`: easing from the old value to the new one over 900 ms.</summary>
        public double Tick(double now)
        {
            if (easeStart >= 0)
            {
                Shown = Ease(easeFrom, Current, now - easeStart, EaseMs);
                if (now - easeStart >= EaseMs) easeStart = -1;
            }
            return Shown;
        }

        public static double Ease(double from, double to, double elapsed, double ms)
        {
            if (ms <= 0 || elapsed >= ms) return to;
            return Math.Floor(from + (to - from) * elapsed / ms + 0.5);
        }

        public bool Visible => Max > 0;
        public static int FillWidth(double value, double max, int width) => Plate.FillWidth(value, max, width);
        public static string Pair(double value, double max) => Plate.Short(value) + " / " + Plate.Short(max);
        public void Clear() { Current = Max = 0; Shown = 0; easeStart = -1; }
    }

    /// <summary>Monk chi pips (opcode 247): plain text "chi:chi:max:decaySec". The server drops chi untouched for decay seconds, so the pips empty at the same time.</summary>
    public sealed class MonkChi
    {
        public int Chi, Max, Decay;
        public double ReceivedAt;
        public bool Active;
        public Func<double> Clock = () => 0;
        /// <summary>The player's vocation id, for the monk check (0 unknown).</summary>
        public Func<int> Vocation = () => 0;

        public MonkChi(ExtOpcodes e)
        {
            if (e != null) e.OnText(HudOp.MonkChi, wire => Receive(wire, Clock(), Vocation()));
        }

        public static bool IsMonk(int vocation) => vocation >= 17 && vocation <= 19;

        public static bool Parse(string text, out int chi, out int max, out int decay)
        {
            chi = max = decay = 0;
            if (text == null || !text.StartsWith("chi:", StringComparison.Ordinal)) return false;
            var p = text.Split(':');
            if (p.Length != 4) return false;
            var ns = new int[3];
            for (int i = 0; i < 3; i++)
            {
                foreach (char c in p[i + 1]) if (c < '0' || c > '9') return false;
                if (p[i + 1].Length == 0 || !int.TryParse(p[i + 1], NumberStyles.None, CultureInfo.InvariantCulture, out ns[i])) return false;
            }
            chi = ns[0]; max = ns[1]; decay = ns[2];
            if (chi > max) chi = max;
            return true;
        }

        /// <summary>Applies a message. A character who is not a Monk gets max 0 (the HUD hides). `vocation` 0 (unknown) does not hide.</summary>
        public bool Receive(string text, double now, int vocation)
        {
            if (!Parse(text, out int chi, out int max, out int decay)) return false;
            if (max > 0 && vocation != 0 && !IsMonk(vocation)) max = 0;
            Chi = chi; Max = max; Decay = decay; ReceivedAt = now;
            Active = max > 0;
            return true;
        }

        /// <summary>Chi at `now` (0 once it decayed).</summary>
        public int Shown(double now)
        {
            if (Max <= 0) return 0;
            if (Decay > 0 && (now - ReceivedAt) / 1000.0 >= Decay) return 0;
            return Chi;
        }

        /// <summary>The look of pip i (1-based): full, empty or hidden.</summary>
        public static string Pip(int i, int chi, int max) => i > max ? "hidden" : i <= chi ? "full" : "empty";

        /// <summary>Seconds until the chi fades; -1 when nothing fades.</summary>
        public double FadeIn(double now)
        {
            if (Chi <= 0 || Decay <= 0) return -1;
            return Math.Max(0, Decay - (now - ReceivedAt) / 1000.0);
        }

        public void Clear() { Chi = Max = Decay = 0; Active = false; }
    }

    // ============================================================================================================== monster bar
    public sealed class MonsterInfo
    {
        public string Tier = "", Label = "", Role = "";
        public int Level;
        public List<string> Mods = new List<string>();
    }

    public sealed class MechCast
    {
        public uint Cid;
        public string Boss = "", Label = "", Kind = "telegraph";
        public double StartAt, EndAt, Ms;
    }

    /// <summary>The tiered target bar (opcode 125): the server names a monster's tier, label, role, level and modifiers on a query; boss mechanics come as `mech`.</summary>
    public sealed class MonsterBar
    {
        public static readonly Dictionary<string, (string name, string label, string world, bool role)> Styles =
            new Dictionary<string, (string, string, string, bool)>
        {
            { "normal", ("#d6c9ae", "", null, false) },
            { "magic", ("#7fb0ff", "Magic", "#7fb0ff", false) },
            { "rare", ("#f6cf72", "Rare", "#f6cf72", false) },
            { "legendary", ("#ff9a4a", "Legendary", "#ff9a4a", false) },
            { "boss", ("#ff6a50", "", "#ff6a50", false) },
            { "guardian", ("#ff6a50", "Rift Guardian", "#ff6a50", true) },
            { "omen", ("#c79bff", "Omen Guardian", "#c79bff", true) },
        };

        public static readonly Dictionary<string, string> Mods = new Dictionary<string, string>
        {
            { "blazing", "Blazing: its hits may set you on fire (30%)." },
            { "chilling", "Chilling: its hits may slow you for 3 seconds (25%)." },
            { "venomous", "Venomous: its hits may poison you (30%)." },
            { "shocking", "Shocking: its hits may electrify you (25%)." },
            { "vampiric", "Vampiric: heals 30% of the damage it deals." },
            { "berserker", "Berserker: deals 50% more damage below half health." },
            { "brutal", "Brutal: deals 40% more damage." },
            { "stoneskin", "Stoneskin: takes 30% less damage." },
            { "reflective", "Reflective: returns 15% of the damage it takes." },
            { "regenerating", "Regenerating: heals 2% of its health every 2.5 seconds." },
            { "swift", "Swift: moves faster." },
            { "explosive", "Explosive: explodes on death (5% of its health, 2 tiles)." },
            { "juggernaut", "Juggernaut: 60% more health." },
        };

        public const double TrailHold = 350, TrailSpeed = 60, TrailEase = 0.006, MechHoldMs = 600;
        public static readonly Dictionary<string, string> MechColors = new Dictionary<string, string>
        {
            { "telegraph", "#c0392b" }, { "channel", "#8e44ad" }, { "soak", "#2e9e5b" }, { "los", "#2a6fb0" }, { "interrupted", "#7d7176" },
        };
        public static readonly Dictionary<string, string> MechHints = new Dictionary<string, string>
        {
            { "telegraph", "move out" }, { "channel", "kill the totem" }, { "soak", "stand in the circle" }, { "los", "hide behind a pillar" }, { "interrupted", "interrupted" },
        };

        readonly Dictionary<uint, MonsterInfo> info = new Dictionary<uint, MonsterInfo>();
        readonly Dictionary<uint, double> asked = new Dictionary<uint, double>();
        public uint Target;
        public string TargetName = "";
        public int Percent = 100, LastPercent = 100;
        public double TrailValue = 100, TrailHoldLeft;
        public MechCast Mech;
        public Func<double> Clock = () => 0;
        readonly ExtOpcodes ext;

        public MonsterBar(ExtOpcodes e)
        {
            ext = e;
            if (e != null) e.On(HudOp.MonsterBar, m => Receive(m.Action, m.Data, Clock()));
        }

        public void Receive(string action, object d, double now)
        {
            if (action == "mech") { var c = StartMech(d, now); if (c != null) Mech = PickMech(Mech, c); }
            else if (action == "info" && Json.Get(d, "cid") != null)
            {
                uint cid = (uint)Json.Number(d, "cid");
                var mi = new MonsterInfo { Tier = Json.Text(d, "tier"), Label = Json.Text(d, "label"), Role = Json.Text(d, "role"), Level = Json.Int(d, "level") };
                if (mi.Level == 0 && info.TryGetValue(cid, out var old)) mi.Level = old.Level;
                foreach (var m in Json.List(d, "mods")) if (m is string ms) mi.Mods.Add(ms);
                info[cid] = mi;
            }
        }

        public MonsterInfo Info(uint cid) => info.TryGetValue(cid, out var i) ? i : null;
        public string Tier(uint cid) => Info(cid)?.Tier;
        public string Role(uint cid) => Info(cid)?.Role;

        /// <summary>Asks for a creature's tier (a creature once per 30 s at most: a crowd in view must not flood the server).</summary>
        public bool Query(uint cid, double now, bool force = false)
        {
            if (cid == 0) return false;
            if (!force && asked.TryGetValue(cid, out var at) && now - at < 30000) return false;
            asked[cid] = now;
            return ext != null && ext.Send(HudOp.MonsterBar, "query", new Dictionary<string, object> { { "cid", (double)cid } });
        }

        /// <summary>Called each frame with the attacked creature (0 none) and its health percent: asks the server on a new target and moves the damage trail.</summary>
        public void Update(uint target, string name, int percent, double now, double dtMs)
        {
            if (target != Target)
            {
                Target = target;
                TargetName = name ?? "";
                Percent = LastPercent = percent;
                TrailValue = percent;
                TrailHoldLeft = 0;
                if (target != 0) Query(target, now, true);   // asked on every new target: the level after the name can change
            }
            else if (target != 0)
            {
                TargetName = name ?? TargetName;
                if (percent != Percent)
                {
                    TrailHit(LastPercent, percent);
                    LastPercent = percent;
                    Percent = percent;
                }
                TrailStep(Percent, dtMs);
            }
        }

        public static string StyleKey(string tier, string role)
        {
            if (!string.IsNullOrEmpty(role) && Styles.ContainsKey(role)) return role;
            if (!string.IsNullOrEmpty(tier) && Styles.ContainsKey(tier)) return tier;
            return "normal";
        }

        public string Key(uint cid) { var i = Info(cid); return StyleKey(i?.Tier, i?.Role); }

        /// <summary>The name line: the server's label (Magic, Rare ...) or the style's, then the name; a role's tag wins over the tier's.</summary>
        public static string Title(string key, string label, string name)
        {
            var st = Styles.ContainsKey(key) ? Styles[key] : Styles["normal"];
            string tag = (!st.role && !string.IsNullOrEmpty(label)) ? label : st.label;
            return tag.Length == 0 ? name : Loc.T(tag) + " " + name;
        }

        public static string LevelText(int level) => level > 0 ? Loc.T("Lv {0}", level) : null;
        public static string PercentText(int percent) => Math.Max(0, Math.Min(100, percent)) + "%";

        public static int FillWidth(double percent, int width)
        {
            percent = Math.Max(0, Math.Min(100, percent));
            int px = (int)Math.Floor(width * percent / 100 + 0.5);
            if (percent > 0 && px < 1) px = 1;
            return px;
        }

        /// <summary>The tooltip of a modifier chip: its text, or its name when unknown.</summary>
        public static string ModTip(string name)
        {
            var sb = new StringBuilder();
            foreach (char c in name ?? "") if (char.IsLetter(c)) sb.Append(char.ToLowerInvariant(c));
            return Mods.TryGetValue(sb.ToString(), out var tip) ? Loc.T(tip) : (name ?? "?");
        }

        // damage trail: the part of the bar just lost stays lit, holds a moment, then shrinks to the health
        void TrailHit(double before, double after)
        {
            if (after < before) { TrailValue = Math.Max(TrailValue, before); TrailHoldLeft = TrailHold; }
            if (after >= TrailValue) { TrailValue = after; TrailHoldLeft = 0; }
        }

        /// <summary>One step of dt ms toward the health; true while it still moves.</summary>
        public bool TrailStep(double health, double dt)
        {
            if (TrailValue <= health) { TrailValue = health; TrailHoldLeft = 0; return false; }
            if (TrailHoldLeft > 0) { TrailHoldLeft = Math.Max(0, TrailHoldLeft - dt); return true; }
            double gap = TrailValue - health;
            double step = Math.Max(TrailSpeed * dt / 1000, gap * Math.Min(1, TrailEase * dt));
            TrailValue = Math.Max(health, TrailValue - step);
            return TrailValue > health;
        }

        // boss mechanics cast bar
        public static MechCast StartMech(object d, double now)
        {
            if (!(Json.Get(d, "label") is string label) || !(Json.Get(d, "ms") is double ms)) return null;
            string kind = MechColors.ContainsKey(Json.Text(d, "kind")) ? Json.Text(d, "kind") : "telegraph";
            double len = Math.Max(0, Math.Floor(ms));
            return new MechCast
            {
                Cid = Json.Get(d, "cid") is double c ? (uint)c : 0,
                Boss = Json.Get(d, "boss") is string b ? b : "",
                Label = label, Kind = kind, StartAt = now, EndAt = now + len, Ms = len,
            };
        }

        /// <summary>An "interrupted" cast replaces the running cast of its boss and keeps its label.</summary>
        public static MechCast PickMech(MechCast current, MechCast incoming)
        {
            if (incoming == null) return current;
            if (incoming.Kind == "interrupted" && current != null && current.Cid == incoming.Cid) incoming.Label = current.Label;
            return incoming;
        }

        public static bool MechVisible(MechCast c, double now) => c != null && now <= c.EndAt + MechHoldMs;
        public static double MechProgress(MechCast c, double now) => c.Ms > 0 ? Math.Min(1, (now - c.StartAt) / c.Ms) : 1;

        /// <summary>"Kaelgor: Meteor Rain 2.4s - move out" while it runs; empty when it is over.</summary>
        public static string MechText(MechCast c, double now)
        {
            if (!MechVisible(c, now)) return "";
            string head = c.Boss.Length > 0 ? c.Boss + ": " + c.Label : c.Label;
            if (c.Kind == "interrupted") return head + " - " + Loc.T("interrupted") + "!";
            double left = Math.Max(0, c.EndAt - now);
            if (left <= 0) return head;
            return head + " " + (Math.Floor(left / 100 + 0.5) / 10).ToString("0.0", CultureInfo.InvariantCulture) + "s - " + Loc.T(MechHints[c.Kind]);
        }

        public static int MechFill(MechCast c, double now, int width)
        {
            if (!MechVisible(c, now)) return 0;
            if (c.Kind == "interrupted") return width;
            return (int)Math.Floor(width * MechProgress(c, now) + 0.5);
        }

        /// <summary>Drops a mechanic bar that is over.</summary>
        public void Tick(double now) { if (Mech != null && !MechVisible(Mech, now)) Mech = null; }
        public void Clear() { info.Clear(); asked.Clear(); Target = 0; Mech = null; }
    }

    // ============================================================================================================== anti-bot
    public sealed class AntibotOption { public string Key = ""; public int ClientId; }

    public sealed class AntibotCheck
    {
        public string Token = "", Word = "";
        public List<AntibotOption> Options = new List<AntibotOption>();
        public int Seconds, Attempt = 1, Retries;
    }

    public sealed class ReportReason { public string Key = "", Name = ""; }

    /// <summary>The presence check and the player report (opcode 211): click the picture of the word, with a countdown; a report with name, reason and note.</summary>
    public sealed class Antibot
    {
        public const int NoteMax = 200;
        public AntibotCheck Check;
        public double ReceivedAt, TotalSeconds;
        public string Status = "";
        public bool StatusGood, StatusBad, Locked;
        public double CloseAt = -1;
        // report dialog
        public bool ReportOpen;
        public string ReportName = "", ReportStatus = "";
        public bool ReportStatusGood, ReportSent;
        public List<ReportReason> Reasons = DefaultReasons();
        public int ReportNoteMax = NoteMax;
        public Func<double> Clock = () => 0;
        readonly ExtOpcodes ext;

        public Antibot(ExtOpcodes e)
        {
            ext = e;
            if (e != null) e.On(HudOp.Antibot, m => Receive(m.Action, m.Data, Clock()));
        }

        public static List<ReportReason> DefaultReasons() => new List<ReportReason>
        {
            new ReportReason { Key = "botting", Name = "Botting" }, new ReportReason { Key = "cheating", Name = "Cheating / exploiting" },
            new ReportReason { Key = "harassment", Name = "Harassment" }, new ReportReason { Key = "scam", Name = "Scam" },
            new ReportReason { Key = "name", Name = "Offensive name" }, new ReportReason { Key = "other", Name = "Other" },
        };

        /// <summary>check {t, w, o = [{k, c}], s, a, r}; null when it is not a usable check (two to six options, token and word set).</summary>
        public static AntibotCheck ParseCheck(object d)
        {
            string token = Json.Get(d, "t") as string, word = Json.Get(d, "w") as string;
            if (string.IsNullOrEmpty(token) || token.Length > 32 || string.IsNullOrEmpty(word) || word.Length > 40) return null;
            var list = Json.List(d, "o");
            var c = new AntibotCheck { Token = token, Word = word };
            for (int i = 0; i < list.Count && i < 6; i++)
            {
                string key = Json.Get(list[i], "k") as string;
                double id = Json.Number(list[i], "c");
                if (string.IsNullOrEmpty(key) || key.Length > 16 || id <= 0) return null;
                c.Options.Add(new AntibotOption { Key = key, ClientId = (int)Math.Floor(id) });
            }
            if (c.Options.Count < 2) return null;
            c.Seconds = Math.Max(0, (int)Math.Floor(Json.Number(d, "s")));
            c.Attempt = Math.Max(1, (int)Math.Floor(Json.Number(d, "a", 1)));
            c.Retries = Math.Max(0, (int)Math.Floor(Json.Number(d, "r")));
            return c;
        }

        public static string Prompt(string word) => Loc.T("Click the picture of: {0}", word);
        public static string TimeText(double seconds) { int s = (int)Math.Max(0, Math.Floor(seconds)); return (s / 60) + ":" + (s % 60).ToString("00", CultureInfo.InvariantCulture); }
        /// <summary>Colour of the countdown: red at 10 s or less, amber at 25 s or less.</summary>
        public static string TimeColor(double seconds) => seconds <= 10 ? "#e03a1e" : seconds <= 25 ? "#e8b84a" : "#d6c9ae";
        public static int TimePercent(double seconds, double total) => total <= 0 ? 0 : (int)Math.Max(0, Math.Min(100, Math.Floor(seconds * 100 / total + 0.5)));
        public static string RetryText(int retries) => retries > 0 ? Loc.T("Another picture") : Loc.T("No more pictures");

        public double SecondsLeft(double now) => Check == null ? 0 : Math.Max(0, Check.Seconds - (now - ReceivedAt) / 1000.0);

        public void Receive(string action, object d, double now)
        {
            switch (action)
            {
                case "check":
                {
                    var c = ParseCheck(d);
                    if (c == null) return;
                    Check = c;
                    ReceivedAt = now;
                    if (c.Attempt <= 1) TotalSeconds = Math.Max(1, c.Seconds);
                    Locked = false;
                    CloseAt = -1;
                    Status = c.Attempt > 1 ? Loc.T("A new picture. Take your time.") : "";
                    StatusGood = StatusBad = false;
                    break;
                }
                case "checkResult":
                    if (Check == null) return;
                    if (Json.Truthy(d, "retry"))
                    {
                        Status = Json.Text(d, "text", Loc.T("Try again."));
                        StatusGood = StatusBad = false;
                        return;   // the next picture follows
                    }
                    bool ok = Json.Truthy(d, "ok");
                    Status = Json.Text(d, "text");
                    StatusGood = ok;
                    StatusBad = !ok;
                    Locked = true;
                    CloseAt = now + (ok ? 1500 : 3000);
                    break;
                case "reportOpen":
                    Reasons = ParseReasons(Json.List(d, "reasons"));
                    ReportNoteMax = Json.Get(d, "noteMax") is double nm && nm > 0 ? (int)nm : NoteMax;
                    ReportName = Json.Text(d, "name");
                    ReportStatus = "";
                    ReportSent = false;
                    ReportOpen = true;
                    break;
                case "reportResult":
                    ReportStatus = Json.Text(d, "text");
                    ReportStatusGood = Json.Truthy(d, "ok");
                    ReportSent = ReportStatusGood;
                    if (ReportStatusGood) ReportCloseAt = now + 2500;
                    break;
            }
        }

        public double ReportCloseAt = -1;

        public static List<ReportReason> ParseReasons(List<object> list)
        {
            var o = new List<ReportReason>();
            foreach (var r in list)
            {
                string k = Json.Get(r, "k") as string, n = Json.Get(r, "n") as string;
                if (!string.IsNullOrEmpty(k) && k.Length <= 16 && !string.IsNullOrEmpty(n) && n.Length <= 40) o.Add(new ReportReason { Key = k, Name = n });
            }
            return o.Count == 0 ? DefaultReasons() : o;
        }

        /// <summary>Closes the check and the report window when their timers end.</summary>
        public void Tick(double now)
        {
            if (CloseAt >= 0 && now >= CloseAt) { Check = null; CloseAt = -1; Locked = false; }
            if (ReportCloseAt >= 0 && now >= ReportCloseAt) { ReportOpen = false; ReportCloseAt = -1; }
        }

        public bool Answer(string key)
        {
            if (Check == null || Locked) return false;
            Locked = true;
            Status = Loc.T("Checking...");
            StatusGood = StatusBad = false;
            return ext != null && ext.Send(HudOp.Antibot, "answer", new Dictionary<string, object> { { "t", Check.Token }, { "k", key } });
        }

        public bool Another()
        {
            if (Check == null || Check.Retries <= 0 || Locked) return false;
            Locked = true;
            return ext != null && ext.Send(HudOp.Antibot, "another", new Dictionary<string, object> { { "t", Check.Token } });
        }

        // ---- reports
        /// <summary>The report dialog goes through the server (it sends the reasons), prefilled with a name.</summary>
        public void OpenReport(string name)
        {
            ReportName = name ?? "";
            ext?.Send(HudOp.Antibot, "reportOpen", new Dictionary<string, object> { { "name", ReportName } });
        }

        public static string CleanNote(string note, int max = NoteMax)
        {
            var sb = new StringBuilder();
            bool space = true;
            foreach (char c in note ?? "")
            {
                bool ws = char.IsControl(c) || char.IsWhiteSpace(c);
                if (c > 127 && !ws) continue;   // plain ASCII only, as the main client
                if (ws) { if (!space) sb.Append(' '); space = true; }
                else { sb.Append(c); space = false; }
            }
            string s = sb.ToString().TrimEnd();
            return s.Length > max ? s.Substring(0, max) : s;
        }

        public static bool ValidName(string name)
        {
            if (name == null || name.Length < 2 || name.Length > 29) return false;
            if (!((name[0] >= 'A' && name[0] <= 'Z') || (name[0] >= 'a' && name[0] <= 'z'))) return false;
            foreach (char c in name)
                if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == ' ' || c == '\'' || c == '-')) return false;
            return true;
        }

        /// <summary>The same rules as the server (reports_core.lua): null and an error text, or the message.</summary>
        public static Dictionary<string, object> ReportMessage(string name, string reason, string note, string ownName, int noteMax, out string error)
        {
            error = null;
            name = (name ?? "").Trim();
            if (!ValidName(name)) { error = Loc.T("Type the name of the character you want to report."); return null; }
            if (!string.IsNullOrEmpty(ownName) && string.Equals(name, ownName, StringComparison.OrdinalIgnoreCase)) { error = Loc.T("You cannot report yourself."); return null; }
            if (string.IsNullOrEmpty(reason)) { error = Loc.T("Choose a reason."); return null; }
            note = CleanNote(note, noteMax);
            if (reason == "other" && note.Length < 3) { error = Loc.T("Describe the problem in the note (reason Other)."); return null; }
            return new Dictionary<string, object> { { "name", name }, { "reason", reason }, { "note", note } };
        }

        public bool SendReport(string name, string reason, string note, string ownName)
        {
            var msg = ReportMessage(name, reason, note, ownName, ReportNoteMax, out string err);
            if (msg == null) { ReportStatus = err; ReportStatusGood = false; return false; }
            ReportStatus = "";
            return ext != null && ext.Send(HudOp.Antibot, "report", msg);
        }

        public static string NoteCounter(string note, int max = NoteMax) => (note ?? "").Length + "/" + max;
        /// <summary>The right-click menu entry: players other than yourself.</summary>
        public static bool CanReport(bool isPlayer, bool isLocalPlayer) => isPlayer && !isLocalPlayer;

        public void Clear() { Check = null; CloseAt = -1; ReportOpen = false; ReportCloseAt = -1; Locked = false; }
    }

    // ============================================================================================================== options
    /// <summary>The settings the server wants told: keep attacking while moving (186), right-click equips (188), the display scale it answers (157) and the language of its texts (157 hello).</summary>
    public sealed class HudOptions
    {
        public const string PrefKite = "chaos.kitewalk", PrefEquip = "chaos.rightclickequip", PrefLang = "chaos.lang";
        public bool KeepAttacking = true, RightClickEquips = true;
        /// <summary>The factor of the own level (the server scales damage numbers, health and others itself: this is for numbers worked out locally).</summary>
        public int ScaleFactor = 1, ScaleLevel;
        public HashSet<int> MultiUseIds = new HashSet<int>();
        bool? lastKite, lastEquip;
        public const int MaxFactor = 1000000000;
        readonly ExtOpcodes ext;

        public HudOptions(ExtOpcodes e)
        {
            ext = e;
            if (e != null)
            {
                e.On(HudOp.Scale, m => ReceiveScale(m.Action, m.Data));
                e.On(HudOp.RightClickEquip, m => { if (m.Action == "multiuse") MultiUseIds = IdSet(Json.List(m.Data, "ids")); });
            }
        }

        /// <summary>An unset option or anything but an explicit "off" is on (the default).</summary>
        public static bool IsOn(string value) => !(value == "0" || value == "false" || value == "off");

        public static bool NeedsSend(bool? last, bool on, bool force) => force || last == null || last.Value != on;

        public static Dictionary<string, object> OnMessage(bool on) => new Dictionary<string, object> { { "on", on } };

        /// <summary>Tells the server both options and the language, as the main client does at every game start.</summary>
        public void SendAll(string lang)
        {
            lastKite = lastEquip = null;
            SendKite(true);
            SendEquip(true);
            SendHello(lang);
        }

        // The two option messages have no action: the body is {"on": bool} (kitewalklogic.lua message).
        public void SendKite(bool force)
        {
            if (!NeedsSend(lastKite, KeepAttacking, force)) return;
            if (ext != null && ext.SendText(HudOp.KiteWalk, Json.Serialize(OnMessage(KeepAttacking)))) lastKite = KeepAttacking;
        }

        public void SendEquip(bool force)
        {
            if (!NeedsSend(lastEquip, RightClickEquips, force)) return;
            if (ext != null && ext.SendText(HudOp.RightClickEquip, Json.Serialize(OnMessage(RightClickEquips)))) lastEquip = RightClickEquips;
        }

        public void SetKeepAttacking(bool on) { KeepAttacking = on; SendKite(false); }
        public void SetRightClickEquips(bool on) { RightClickEquips = on; SendEquip(false); }

        public static Dictionary<string, object> HelloMessage(string lang) => new Dictionary<string, object> { { "lang", Loc.Normalize(lang) ?? Loc.English } };

        /// <summary>Hello on opcode 157: the display scale answers, and the server writes its texts in this language.</summary>
        public void SendHello(string lang) { ext?.Send(HudOp.Scale, "hello", HelloMessage(lang)); }

        /// <summary>scale {level, f}: whole factor 1..1e9, else ignored.</summary>
        public bool ReceiveScale(string action, object d)
        {
            if (action != "scale") return false;
            double f = Json.Number(d, "f");
            if (double.IsNaN(f) || f < 1 || f > MaxFactor) return false;
            ScaleFactor = (int)Math.Floor(f);
            ScaleLevel = (int)Math.Floor(Json.Number(d, "level"));
            return true;
        }

        /// <summary>The own level changed (and is not the level of the last factor): ask again.</summary>
        public bool LevelChanged(int level) => level > 0 && ScaleLevel > 0 && level != ScaleLevel;

        /// <summary>n x factor, rounded.</summary>
        public double Scaled(double n) => ScaleFactor == 1 ? n : Math.Floor(n * ScaleFactor + 0.5);

        public static HashSet<int> IdSet(List<object> ids)
        {
            var set = new HashSet<int>();
            foreach (var o in ids) if (o is double d) set.Add((int)d);
            return set;
        }

        public void Reset() { ScaleFactor = 1; ScaleLevel = 0; MultiUseIds.Clear(); lastKite = lastEquip = null; }

        /// <summary>The language names a selector offers: code and the name in its own language.</summary>
        public static readonly string[][] LanguageChoices = { new[] { Loc.Portuguese, "Português (Brasil)" }, new[] { Loc.English, "English" } };
    }

    /// <summary>All the HUD models of one session.</summary>
    public sealed class HudState
    {
        public readonly ToastCenter Toasts;
        public readonly BuffBar Buffs;
        public readonly CastBar Cast;
        public readonly EnergyShield Shield;
        public readonly MonkChi Chi;
        public readonly MonsterBar Monster;
        public readonly Antibot Bot;
        public readonly HudOptions Options;
        bool sent;

        public HudState(ExtOpcodes ext, Func<double> clock, Func<int> vocation)
        {
            Toasts = new ToastCenter(ext) { Clock = clock };
            Buffs = new BuffBar(ext) { Clock = clock };
            Cast = new CastBar(ext) { Clock = clock };
            Shield = new EnergyShield(ext) { Clock = clock };
            Chi = new MonkChi(ext) { Clock = clock, Vocation = vocation };
            Monster = new MonsterBar(ext) { Clock = clock };
            Bot = new Antibot(ext) { Clock = clock };
            Options = new HudOptions(ext);
        }

        /// <summary>Once after the login: the options, the language, the shield hello and the buff sync.</summary>
        public void Hello(string lang)
        {
            if (sent) return;
            sent = true;
            Options.SendAll(lang);
            Shield.Hello();
            Buffs.Sync();
        }

        /// <summary>Per frame: timers of the toasts, cast bars, anti-bot, buff pruning.</summary>
        public void Tick(double now)
        {
            Toasts.Tick(now);
            Cast.Tick(now);
            Bot.Tick(now);
            Monster.Tick(now);
            Buffs.Prune(now);
            Shield.Tick(now);
        }
    }
}
