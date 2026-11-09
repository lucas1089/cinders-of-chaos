// A new player's first hour on a live server (O433 phase 27): newplayer (a fresh character's first login, every packet and extended opcode of its first 45 seconds), firstkill
// (the first honest kill with the class's first attack spell or melee, the loot bag, experience) and firstquest (the first tale of the Archivist from the teleport room market to
// the turn-in, with a level up), riftkilled (a mortal killed by rift monsters, no staff help). Same rules as LiveScenarios.cs: opt-in by --scenario, a time limit, a pass, fail or
// skip with the reason, names scrubbed from the reports. The first three need no staff right and no local-only script; riftkilled needs the local-only helper /rgive for the key
// (a mortal has no /rift key). unity/README.md "A new player's first hour (phase 27)".
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace Chaos.Core.LiveCheck
{
    public sealed partial class LiveRun
    {
        // ------------------------------------------------------------------------------------ the first login timeline
        /// <summary>The seconds of a first login the newplayer scenario looks at: the kit and the welcome come 2.5 s after the entry, the first hint about 9 s later, the Tale of
        /// Cinderhold's introduction 30 s after the welcome (newplayer_config.lua welcome.delayMs, firsthour_config.lua delayMs, tales_config.lua story.delayMs).</summary>
        public const double FirstLoginWindowMs = 45000;

        sealed class TlEntry
        {
            public double T;
            public string Kind = "", Text = "";
        }

        readonly List<TlEntry> timeline = new List<TlEntry>();
        readonly Dictionary<byte, double> packetFirstAt = new Dictionary<byte, double>();
        readonly Dictionary<byte, int> tlExtCount = new Dictionary<byte, int>();
        Dictionary<byte, int> loginSeen;
        int loginFailures, loginUnknown, loginExtBad, tlSaid, tlModals;
        long tlNext;

        void Tl(string kind, string text)
        {
            if (timeline.Count < 600) timeline.Add(new TlEntry { T = s.Now - startedAt, Kind = kind, Text = text });
        }

        /// <summary>Called by Hook for every extended opcode message (raw text), until the window is over.</summary>
        void TimelineExt(byte op, string data)
        {
            if (s.Now - startedAt > FirstLoginWindowMs) return;
            tlExtCount[op] = tlExtCount.TryGetValue(op, out int n) ? n + 1 : 1;
            string action = "";
            if (data.Length > 0 && data[0] == '{')
            {
                var root = Chaos.Core.Json.TryParse(data);
                if (root != null) action = Chaos.Core.Json.Text(root, "action");
            }
            else if (data.Length > 0 && (data[0] == 'S' || data[0] == 'P' || data[0] == 'E')) action = "(chunk " + data[0] + ")";
            else action = "(text)";
            Tl("ext", op + " " + (ops.TryGetValue(op, out var st) ? st.Plan.Name : "not in the table") + " " + action + " " + data.Length + "b");
        }

        /// <summary>Called by Pump: the first time every packet type was seen, the server lines and the windows with their time, and the counts at the end of the window.</summary>
        void TimelineTick()
        {
            if (me == null || s == null || Tick < tlNext) return;
            tlNext = Tick + 20;
            double t = s.Now - startedAt;
            if (loginSeen != null && t > FirstLoginWindowMs + 2000) return;
            foreach (var kv in s.Parser.Seen) if (!packetFirstAt.ContainsKey(kv.Key)) packetFirstAt[kv.Key] = t;
            for (; tlSaid < me.Said.Count; tlSaid++)
            {
                var l = me.Said[tlSaid];
                if (t <= FirstLoginWindowMs) Tl("text", (l.Who.Length > 0 ? l.Who + ": " : "") + "[" + l.Type + "] " + l.Text.Replace("\n", " "));
            }
            var m = s.Parser.Modals;
            if (m.Received > tlModals)
            {
                tlModals = m.Received;
                if (t <= FirstLoginWindowMs && m.Current != null) Tl("modal", ModalLine(m.Current));
            }
            if (loginSeen == null && t >= FirstLoginWindowMs)
            {
                loginSeen = new Dictionary<byte, int>(s.Parser.Seen);
                loginFailures = s.Parser.FailureCount;
                loginUnknown = s.Parser.Failures.Count(f => f.Unknown);
                loginExtBad = ExtBad();
            }
        }

        /// <summary>The first-login lines for the report notes: what came at which second.</summary>
        IEnumerable<string> TimelineLines(string kind) => timeline.Where(x => x.Kind == kind).Select(x => (x.T / 1000).ToString("0.0", CultureInfo.InvariantCulture) + " s " + x.Text);

        /// <summary>The extended opcodes outside the table that a first login brings: the base modules (89 tasks, 92 faction coins, 99 and 106 stats and upgrade points, 181) and the guard
        /// challenge (0, 189). Unity does not read them (docs/UNITY_PARITY.md); any other opcode in a first login is a message Core has no reader for.</summary>
        static readonly HashSet<byte> KnownUnread = new HashSet<byte> { 0, 89, 92, 99, 106, 181, 189 };

        /// <summary>The ext lines of the first login grouped by what they carry: "opcode name action xN @first second".</summary>
        List<string> TimelineExtGrouped()
        {
            var order = new List<string>();
            var first = new Dictionary<string, double>();
            var count = new Dictionary<string, int>();
            foreach (var e in timeline.Where(x => x.Kind == "ext"))
            {
                int sp = e.Text.LastIndexOf(' ');
                string key = sp > 0 ? e.Text.Substring(0, sp) : e.Text;
                if (!count.ContainsKey(key)) { order.Add(key); first[key] = e.T; count[key] = 0; }
                count[key]++;
            }
            return order.Select(k => k + " x" + count[k] + " @" + (first[k] / 1000).ToString("0.0", CultureInfo.InvariantCulture)).ToList();
        }

        bool SawText(string part) => timeline.Any(x => x.Kind == "text" && x.Text.IndexOf(part, StringComparison.OrdinalIgnoreCase) >= 0);
        double? TextAt(string part) { var e = timeline.FirstOrDefault(x => x.Kind == "text" && x.Text.IndexOf(part, StringComparison.OrdinalIgnoreCase) >= 0); return e == null ? (double?)null : e.T / 1000; }

        // ------------------------------------------------------------------------------------ newplayer
        /// <summary>A fresh character's first login: the packets and extended opcodes of its first 45 seconds (every one read, none unknown, no handler error), the start level and the
        /// kit, the welcome, the hints that come on their own, the outfit window the base first login opens (answered the way a player does: OK, then another look) and the spells the
        /// class has at once. Skips when the character is not new (no kit line in the first seconds).</summary>
        void ScNewPlayer(ScenarioResult r)
        {
            // a character that is not new has no kit line in the first seconds: no need to wait out the window
            TimelineTick();
            if (s.Now - startedAt > 8000 && !(SawText("starter kit") || SawText("starter gear"))) { r.Skip("not a first login: no starter kit line in the first " + (int)((s.Now - startedAt) / 1000) + " s (character level " + level + " at the character list); run it on a character that never logged in"); return; }
            double left = FirstLoginWindowMs - (s.Now - startedAt);
            if (left > 0) Pump((int)left + 300, () => s.Closed != null);
            TimelineTick();
            var p = s.Parser;
            var problems = new StringBuilder();
            bool kitLine = SawText("starter kit") || SawText("starter gear");
            if (!kitLine) { r.Skip("not a first login: no starter kit line in the first " + (int)(FirstLoginWindowMs / 1000) + " s (character level " + level + " at the character list); run it on a character that never logged in"); return; }
            foreach (string line in TimelineLines("text").Where(l => l.IndexOf("Top Level", StringComparison.Ordinal) < 0 && l.IndexOf("boosted", StringComparison.Ordinal) < 0).Take(22)) r.Note("text " + (line.Length > 170 ? line.Substring(0, 170) + "..." : line));
            foreach (string line in TimelineLines("modal")) r.Note("window " + line);
            r.Note("opcodes: " + string.Join("; ", TimelineExtGrouped()));
            r.Note("packet types first seen: " + string.Join(" ", packetFirstAt.OrderBy(kv => kv.Value).Select(kv => kv.Key.ToString("X2", CultureInfo.InvariantCulture) + "@" + (kv.Value / 1000).ToString("0.0", CultureInfo.InvariantCulture))));
            r.Note("counts at 45 s: " + string.Join(" ", (loginSeen ?? p.Seen).OrderBy(kv => kv.Key).Select(kv => kv.Key.ToString("X2", CultureInfo.InvariantCulture) + "x" + kv.Value)) + "; parse failures " + loginFailures + ", unknown " + loginUnknown + ", extended opcode errors " + loginExtBad);

            // ---- every packet read, none unknown, no handler error
            if (loginFailures > 0) problems.Append(loginFailures + " parse failure(s) in the first login (" + string.Join("; ", p.Failures.Take(3).Select(f => f.ToString())) + "); ");
            if (loginUnknown > 0) problems.Append(loginUnknown + " packet type(s) unknown to the parser; ");
            if (loginExtBad > 0) problems.Append(loginExtBad + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            var unread = tlExtCount.Keys.Where(op => !ops.ContainsKey(op) && !KnownUnread.Contains(op)).OrderBy(op => op).ToList();
            if (unread.Count > 0) problems.Append("extended opcode(s) " + string.Join(", ", unread) + " came in the first login and Core has no reader for them; ");

            // ---- the start: level, health, kit, place
            r.Note("character at the list: level " + level + ", vocation " + vocation + "; in game: level " + p.Level + ", health " + p.Health + "/" + p.MaxHealth + ", mana " + p.Mana + "/" + p.MaxMana + ", at " + P(me.Pos) + ", free capacity " + p.FreeCap);
            if (p.Level < 8) problems.Append("level " + p.Level + " after the first login, the start level is 8; ");
            if (p.MaxHealth <= 0 || p.Health != p.MaxHealth) problems.Append("health " + p.Health + "/" + p.MaxHealth + " at the start; ");
            int worn = 0;
            var wornList = new List<string>();
            for (int i = 1; i < p.Inventory.Length; i++) if (p.Inventory[i] != null && i != 3) { worn++; wornList.Add(i + ":" + p.Inventory[i].Id); }
            r.Note("worn: " + worn + " piece(s) [" + string.Join(" ", wornList) + "], backpack " + (p.Inventory.Length > 3 && p.Inventory[3] != null ? p.Inventory[3].Id.ToString(CultureInfo.InvariantCulture) : "none"));
            if (worn < 4) problems.Append("only " + worn + " worn piece(s) of the starter kit; ");
            if (p.Inventory.Length <= 3 || p.Inventory[3] == null) problems.Append("no backpack; ");
            else
            {
                EnsureBagOpen(me);
                Pump(600, () => false);
                var inBag = new List<string>();
                foreach (var c in p.Containers.Values) foreach (var it in c.Items) if (it != null) inBag.Add(it.Id + "x" + Math.Max(1, it.Count));
                r.Note("backpack holds " + inBag.Count + " stack(s): " + string.Join(" ", inBag.Take(14)));
                if (inBag.Count < 4) problems.Append("the starter backpack holds " + inBag.Count + " stack(s), the kit has potions, food, a rope, a shovel, a scroll and gold; ");
            }

            // ---- the texts and toasts that come on their own
            var checks = new[] { ("kit line", "starter kit"), ("welcome", "Welcome,"), ("level line", "You advanced from Level") };
            foreach (var (what, part) in checks) if (!SawText(part)) problems.Append("no '" + part + "' line (" + what + ") in the first login; ");
            double? hintAt = TextAt("First hunts"), storyAt = TextAt("Tale of Cinderhold");
            r.Note("first hint 'First hunts' at " + (hintAt.HasValue ? hintAt.Value.ToString("0.0", CultureInfo.InvariantCulture) + " s" : "never") + ", Tale of Cinderhold introduction at " + (storyAt.HasValue ? storyAt.Value.ToString("0.0", CultureInfo.InvariantCulture) + " s" : "never"));
            if (!hintAt.HasValue) problems.Append("the first hint (firsthour 'start') never came; ");
            if (!storyAt.HasValue) problems.Append("the Tale of Cinderhold introduction never came in 45 s; ");
            if (!tlExtCount.ContainsKey(79)) problems.Append("no toast (opcode 79) in the first login; ");

            // ---- the outfit window of the base first login: 0xC8, answered like a player
            bool asked = SawText("choose your outfit");
            var ow = p.Outfits;
            r.Note("outfit window: asked by the welcome line " + asked + ", opened " + ow.Opens + " time(s), " + ow.Outfits.Count + " outfit(s) [" + string.Join(", ", ow.Outfits.Take(6).Select(x => x.Name + "/" + x.LookType + "/" + x.Addons)) + "], " + ow.Mounts.Count + " mount(s), extras " + ow.HasExtras + " (wings " + ow.Wings.Count + ", auras " + ow.Auras.Count + ", shaders " + ow.Shaders.Count + "), current look " + ow.Current.LookType);
            if (asked && ow.Opens == 0) problems.Append("the welcome line asks to choose an outfit and no outfit window (0xC8) came; ");
            if (ow.Opens > 0)
            {
                if (ow.Outfits.Count == 0) problems.Append("the outfit window lists no outfit; ");
                else
                {
                    var own = world.Player;
                    int moved = Seen(0x8E);
                    s.SetOutfit(ow.Current);   // OK with the look on offer
                    Pump(900, () => false);
                    r.Note("outfit window answered OK with the current look " + ow.Current.LookType + ": 0x8E +" + (Seen(0x8E) - moved) + ", own look " + (own != null ? own.Outfit.LookType : 0) + ", window open " + ow.Open);
                    if (ow.Open) problems.Append("the outfit window stayed open after the answer; ");
                    var other = ow.Outfits.FirstOrDefault(x => x.LookType != ow.Current.LookType);
                    if (other != null)
                    {
                        var cur = ow.Current;
                        var pick = new Outfit { LookType = other.LookType, Head = cur.Head, Body = cur.Body, Legs = cur.Legs, Feet = cur.Feet, Addons = other.Addons, Mount = cur.Mount, Wings = cur.Wings, Aura = cur.Aura, Shader = cur.Shader };
                        int moved2 = Seen(0x8E);
                        int say0 = me.Said.Count;
                        s.SetOutfit(pick);
                        bool applied = WaitFor(3000, () => own != null && own.Outfit.LookType == pick.LookType);
                        r.Note("outfit " + other.Name + " (look " + other.LookType + ", addons " + other.Addons + ") chosen: " + (applied ? "applied" : "not applied") + ", 0x8E +" + (Seen(0x8E) - moved2) + ", server said [" + string.Join(" | ", me.ServerTexts(say0).Take(2)) + "]");
                        if (!applied) problems.Append("the chosen outfit " + other.LookType + " was not applied (the player is " + (own != null ? own.Outfit.LookType : 0) + "); ");
                        else s.SetOutfit(cur);   // back to the class look
                        Pump(600, () => false);
                    }
                }
            }
            else r.Note("no outfit window came (the base first login sends it when the character's outfit was never chosen)");

            // ---- the spells the class has at once
            if (!s.Spells.Loaded) { s.Spells.Open(); WaitFor(5000, () => s.Spells.Loaded); }
            var attack = s.Spells.Loaded ? s.Spells.Visible(SpellBook.FilterLearned, "attack", "") : new List<Spell>();
            var all = s.Spells.Loaded ? s.Spells.Visible(SpellBook.FilterLearned, "all", "") : new List<Spell>();
            r.Note("spells ready at level " + p.Level + ": " + all.Count + " (" + attack.Count + " attack) [" + string.Join(", ", all.Take(8).Select(x => x.Name + " L" + x.Level + " " + x.Mana + "mp")) + "]");
            if (!s.Spells.Loaded) problems.Append("the spell list never arrived; ");
            else if (attack.Count == 0) problems.Append("no attack spell ready at the start level (every class has one at level 8); ");
            if (s.Closed != null) problems.Append("the connection closed: " + s.Closed + "; ");
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else
            {
                // the server's own pushes and the answers to the session's hellos come in the first seconds; the opcode requests of the live check's own sweep (from 4.5 s, unless --no-ext) add the rest
                var early = new HashSet<string>(timeline.Where(x => x.Kind == "ext" && x.T <= 4500).Select(x => x.Text.Substring(0, Math.Max(0, x.Text.IndexOf(' ')))));
                r.Pass("first login read whole: " + p.Seen.Count + " packet types, " + early.Count + " extended opcodes in the first 4.5 s (" + tlExtCount.Count + " by 45 s), level " + p.Level + " with " + worn + " worn pieces, welcome, kit, hints, outfit window answered, " + attack.Count + " attack spell(s) ready");
            }
        }

        // ------------------------------------------------------------------------------------ firstkill
        /// <summary>Where the weak monsters of the first hunt live: the Rat spawns of the cellars under Cinderhold (server spawn file, floor 8, south to north), the places the scenario
        /// walks to when no Rat is in view.</summary>
        static readonly Pos[] RatGrounds = { new Pos(32385, 32217, 8), new Pos(32390, 32217, 8), new Pos(32394, 32217, 8), new Pos(32362, 32214, 8), new Pos(32352, 32214, 8), new Pos(32368, 32203, 8) };

        /// <summary>The way from the temple of Cinderhold to the stairs down to the cellars (server map, floor 7: out of the hall by the west side of the north door, round the house to its east side, then south to the stair at 32383,32230). The scenario walks it waypoint by waypoint when no stair is in view; each hop is short and in view.</summary>
        static readonly Pos[] DescentRoute = { new Pos(32366, 32235, 7), new Pos(32366, 32229, 7), new Pos(32368, 32223, 7), new Pos(32374, 32217, 7), new Pos(32380, 32213, 7), new Pos(32384, 32219, 7), new Pos(32387, 32225, 7), new Pos(32390, 32226, 7) };
        /// <summary>The stair the route ends at: it leads into the cave under the city where the Rats live (the stairs the route passes lead to closed cellars under the houses).</summary>
        static readonly Pos DescentStair = new Pos(32390, 32225, 7);
        /// <summary>The way to the cellar stair of the first tale (the house east of the temple: its basement is the cellar the tale sends the player to, 32378,32226,8 is 5 tiles from the landing): round the house to its south side, the stair is north of the last waypoint.</summary>
        static readonly Pos[] CellarRoute = { new Pos(32366, 32235, 7), new Pos(32366, 32229, 7), new Pos(32368, 32223, 7), new Pos(32374, 32217, 7), new Pos(32380, 32213, 7), new Pos(32384, 32219, 7), new Pos(32385, 32225, 7), new Pos(32385, 32231, 7), new Pos(32383, 32231, 7) };
        static readonly Pos CellarStair = new Pos(32383, 32230, 7);
        /// <summary>From the cellar stair to the rat stair: the street east of the house.</summary>
        static readonly Pos[] RatRouteFromCellar = { new Pos(32385, 32225, 7), new Pos(32387, 32225, 7), new Pos(32390, 32226, 7) };
        Pos[] descentRoute = DescentRoute;
        Pos descentTarget = DescentStair;

        Creature NearestMonster(LiveClient a, string name, bool reachable = false)
        {
            Creature best = null;
            int bd = int.MaxValue;
            foreach (var c in a.World.Creatures.Values)
            {
                if (c.Type != 1 || c.Position.X <= 0 || c.Position.Z != a.Pos.Z || c.HealthPercent <= 0) continue;
                if (name != null && !NameIs(c.Name, name)) continue;
                int d = PathFinder.Cheb(c.Position, a.Pos);
                if (d >= bd) continue;
                if (reachable && d > 1 && PathFinder.Find(a.Pos, c.Position, pp => Passable(a.World, pp, a.World.PlayerId), 1) == null) continue;
                bd = d; best = c;
            }
            return best;
        }

        /// <summary>True when the monster's name is the wanted one; a wanted Rat takes a Cave Rat too (the first hunt and the tale of the cellars count both).</summary>
        internal static bool NameIs(string shown, string want)
        {
            string b = BaseName(shown);
            return string.Equals(b, want, StringComparison.OrdinalIgnoreCase) || (string.Equals(want, "Rat", StringComparison.OrdinalIgnoreCase) && string.Equals(b, "Cave Rat", StringComparison.OrdinalIgnoreCase));
        }

        /// <summary>A monster name without the level tag the server appends ("Rat [4]").</summary>
        internal static string BaseName(string n)
        {
            int b = n.LastIndexOf(" [", StringComparison.Ordinal);
            return b > 0 && n.EndsWith("]", StringComparison.Ordinal) ? n.Substring(0, b) : n;
        }

        sealed class FightLog
        {
            public bool Killed, Died, Gone;
            public int Casts, Attacks, ExpTexts, StatsPackets, HealthMin = int.MaxValue;
            public long ExpBefore, ExpAfter, Gain;
            public Pos LastPos;
            public double Ms;
            public readonly List<string> Lines = new List<string>();
        }

        /// <summary>Fights one monster the way a player does: the attack on it (chase on, offensive stance), the class's first attack spell cast whenever it is ready and the monster is near.
        /// The kill counts when the monster left the map and the experience text came. No staff command, no calm.</summary>
        FightLog FightOne(Creature target, Spell spell, int limitMs)
        {
            var p = s.Parser;
            uint id = target.Id;
            var log = new FightLog { LastPos = target.Position, ExpBefore = (long)p.Experience };
            int texts0 = p.ExpGainTexts, say0 = me.Said.Count, stats0 = Seen(0xA0);
            long t0 = Tick;
            long nextAtk = 0, nextCast = Tick + 600;
            s.Attack(id);
            nextAtk = Tick + 2500;
            log.Attacks++;
            while (Tick - t0 < limitMs && s.Closed == null)
            {
                Pump(100, () => p.Dead || !world.Creatures.ContainsKey(id) || world.Creatures[id].Position.X <= 0);
                if (p.Dead) { log.Died = true; break; }
                if (!world.Creatures.TryGetValue(id, out var c) || c.Position.X <= 0) { log.Gone = true; break; }
                log.LastPos = c.Position;
                log.HealthMin = Math.Min(log.HealthMin, p.Health);
                int dist = PathFinder.Cheb(c.Position, me.Pos);
                if (Tick >= nextAtk) { s.Attack(id); log.Attacks++; nextAtk = Tick + 2500; }
                if (spell != null && Tick >= nextCast && dist <= 4 && p.Mana >= spell.Mana && s.Spells.CooldownLeft(spell) <= 0)
                {
                    if (s.Spells.Cast(spell)) log.Casts++;
                    nextCast = Tick + 1500;
                }
            }
            if (log.Gone) WaitFor(2500, () => p.ExpGainTexts > texts0);
            Pump(500, () => false);
            log.ExpTexts = p.ExpGainTexts - texts0;
            log.StatsPackets = Seen(0xA0) - stats0;
            log.ExpAfter = (long)p.Experience;
            log.Gain = p.LastExpGain;
            log.Killed = log.Gone && log.ExpTexts > 0;
            log.Ms = Tick - t0;
            foreach (string t in me.ServerTexts(say0).Where(x => x.IndexOf("hitpoint", StringComparison.OrdinalIgnoreCase) >= 0 || x.IndexOf("experience", StringComparison.OrdinalIgnoreCase) >= 0 || x.IndexOf("advanced", StringComparison.OrdinalIgnoreCase) >= 0).Take(4)) log.Lines.Add(t);
            return log;
        }

        /// <summary>Goes down to the floor of the weak monsters (stairs in view, one after the other) and walks to the Rat grounds until a monster of that name is in view.</summary>
        Creature ReachMonster(ScenarioResult r, string name, StringBuilder problems)
        {
            var found = NearestMonster(me, name, true);
            if (found != null) return found;
            avoidStairs = true;
            try { return ReachMonsterWalk(r, name, problems); } finally { avoidStairs = false; }
        }

        /// <summary>The nearest stair down in view (the search path may end on the stair tile, so the stair refusal of the walks is off while it looks).</summary>
        (Pos tile, string kind)? FindStairDown(bool onlyTarget = false)
        {
            bool was = avoidStairs;
            avoidStairs = false;
            try
            {
                var near = world.Tiles.Where(kv => kv.Key.Z == me.Pos.Z && me.Pos.Z == descentTarget.Z && PathFinder.Cheb(kv.Key, descentTarget) == 0 && FloorChangeOf(kv.Value) == "down").Select(kv => kv.Key).ToList();
                if (near.Count > 0 && PathFinder.Find(me.Pos, near[0], pp => Passable(world, pp, world.PlayerId), 0) != null) return (near[0], "down");
                return onlyTarget ? null : FindFloorChange(me, 1);
            }
            finally { avoidStairs = was; }
        }

        /// <summary>Walks a route of waypoints to a stair and takes it down (the stair is the one at `stair`; the others on the way are left alone). False with the reason in problems.</summary>
        bool GoDown(ScenarioResult r, StringBuilder problems, Pos[] route, Pos stair, string label)
        {
            descentRoute = route;
            descentTarget = stair;
            avoidStairs = true;
            try
            {
                var found = FindStairDown(true);
                if (found == null)
                {
                    foreach (var h in route.Where(h => h.Z == me.Pos.Z))
                    {
                        bool ok = WalkTo(me, h, 1, 60000, false, out string why);
                        if (!ok) { problems.Append(label + ": no way to the waypoint " + P(h) + " from " + P(me.Pos) + ": " + why + "; "); return false; }
                        found = FindStairDown(true);
                        if (found != null) break;
                    }
                }
                if (found == null) { problems.Append(label + ": the stair at " + P(stair) + " never came into view (the character is at " + P(me.Pos) + "); "); return false; }
                var (tile, kind) = found.Value;
                avoidStairs = false;
                return TakeStairs(me, tile, kind, r, label, problems);
            }
            finally { avoidStairs = false; descentRoute = DescentRoute; descentTarget = DescentStair; }
        }

        /// <summary>Takes the way up: the nearest stair or ramp in view, else the ladder (server item 1386, whose use action lifts the character one floor) on or next to its tile, used
        /// the way a player does (a right click on it).</summary>
        bool GoUp(ScenarioResult r, StringBuilder problems, string label)
        {
            var up = FindFloorChange(me, -1);
            if (up != null)
            {
                var (tile, kind) = up.Value;
                return TakeStairs(me, tile, kind, r, label, problems);
            }
            if (serverToClient == null || !serverToClient.TryGetValue(1386, out int ladderCid)) { problems.Append(label + ": no stair up in view of " + P(me.Pos) + " and no ladder item in items.otb; "); return false; }
            // the ladders in view, nearest first; a walk beside one when it is not next to the character
            var ladders = new List<(Pos tile, int stack)>();
            foreach (var kv in world.Tiles)
            {
                if (kv.Key.Z != me.Pos.Z) continue;
                for (int i = 0; i < kv.Value.Things.Count; i++)
                {
                    var th = kv.Value.Things[i];
                    if (!th.IsCreature && th.Item != null && th.Item.Id == ladderCid) ladders.Add((kv.Key, i));
                }
            }
            foreach (var (tp, stack) in ladders.OrderBy(l => PathFinder.Cheb(l.tile, me.Pos)).Take(4))
            {
                bool wasAvoid = avoidStairs;
                avoidStairs = true;
                try
                {
                    if (PathFinder.Cheb(tp, me.Pos) > 1 && !WalkTo(me, tp, 1, 30000, false, out string why)) { r.Note(label + ": no way beside the ladder at " + P(tp) + ": " + why); continue; }
                }
                finally { avoidStairs = wasAvoid; }
                var from = me.Pos;
                int say0 = me.Said.Count;
                s.UseItem(tp, (ushort)ladderCid, (byte)stack);
                bool moved = WaitFor(4000, () => me.Pos.Z != from.Z);
                Pump(1200, () => false);
                r.Note(label + ": ladder at " + P(tp) + " used from " + P(from) + ": " + (moved ? "now at " + P(me.Pos) : "no move") + ", server said [" + string.Join(" | ", me.ServerTexts(say0).Take(2)) + "]");
                if (moved) return true;
            }
            problems.Append(label + ": no stair up and no ladder reachable from " + P(me.Pos) + " (" + ladders.Count + " ladder tile(s) in view); ");
            return false;
        }

        Creature ReachMonsterWalk(ScenarioResult r, string name, StringBuilder problems)
        {
            Creature found = null;
            for (int hop = 0; hop < 3 && found == null; hop++)
            {
                var stair = FindStairDown(true);
                if (stair == null)
                {
                    foreach (var h in descentRoute.Where(h => h.Z == me.Pos.Z))
                    {
                        bool ok = WalkTo(me, h, 1, 60000, false, out string why);
                        r.Note("walk towards the stairs, waypoint " + P(h) + ": " + (ok ? "arrived at " + P(me.Pos) : why));
                        stair = FindStairDown(true);
                        if (stair != null || !ok) break;
                    }
                    stair = stair ?? FindStairDown();
                }
                if (stair == null) break;
                var (tile, kind) = stair.Value;
                var mk = Mark.Of(me);
                avoidStairs = false;
                bool took = TakeStairs(me, tile, kind, r, "descent " + (hop + 1), problems);
                avoidStairs = true;
                if (!took) return null;
                Pump(1200, () => false);
                r.Note("monsters in view on floor " + me.Pos.Z + ": " + string.Join(", ", world.Creatures.Values.Where(c => c.Type == 1 && c.Position.X > 0).Select(c => c.Name + "@" + P(c.Position)).Take(10)));
                found = NearestMonster(me, name, true);
            }
            if (found != null) return found;
            foreach (var g in RatGrounds)
            {
                if (g.Z != me.Pos.Z) continue;
                bool ok = WalkTo(me, g, 3, 40000, false, out string why);
                r.Note("walk to the grounds at " + P(g) + ": " + (ok ? "arrived at " + P(me.Pos) : why));
                found = NearestMonster(me, name, true);
                if (found != null) return found;
            }
            return null;
        }

        /// <summary>The loot container on the tile of a kill (the loot bag of src-patch 0089, or the monster's body on an engine without it): its client id and the stack position.</summary>
        (Pos tile, int stack, int id)? FindLootOn(Pos at)
        {
            for (int dx = -1; dx <= 1; dx++)
                for (int dy = -1; dy <= 1; dy++)
                {
                    var tp = new Pos(at.X + dx, at.Y + dy, at.Z);
                    var t = world.Get(tp);
                    if (t == null) continue;
                    for (int i = t.Things.Count - 1; i >= 0; i--)
                    {
                        var th = t.Things[i];
                        if (th.IsCreature || th.Item == null || th.Item.Type == null || !th.Item.Type.Container) continue;
                        return (tp, i, th.Item.Id);
                    }
                }
            return null;
        }

        /// <summary>Opens the container on the kill's tile, reads it and moves everything in it to the backpack, the way a player does. Returns the problems found (empty when the loot is
        /// in the bag); notes say what was read.</summary>
        string LootKill(ScenarioResult r, Pos at, out int moved, out bool wasBag)
        {
            moved = 0;
            wasBag = false;
            var p = s.Parser;
            var loot = FindLootOn(at);
            if (loot == null) return "no loot container on or beside the kill's tile " + P(at) + " (the corpse or the loot bag)";
            var (tile, stack, cid) = loot.Value;
            int sid = serverToClient == null ? 0 : serverToClient.Where(kv => kv.Value == cid).Select(kv => kv.Key).FirstOrDefault();
            wasBag = sid == 6068;
            if (PathFinder.Cheb(tile, me.Pos) > 1 && !WalkTo(me, tile, 1, 20000, false, out string why)) return "could not walk to the loot at " + P(tile) + ": " + why;
            if (p.Inventory.Length <= 3 || p.Inventory[3] == null) return "no backpack to loot into";
            ushort bagId = (ushort)p.Inventory[3].Id;
            // the backpack as it is before the loot: what it holds by item id
            var snap = OpenBackpackCounts(bagId);
            if (snap == null) return "the backpack did not open";
            var packets0 = new Dictionary<byte, int>(p.Seen);
            int opened0 = Seen(0x6E), say0 = me.Said.Count;
            s.UseItem(tile, (ushort)cid, (byte)stack);
            bool opened = WaitFor(3000, () => Seen(0x6E) > opened0);
            if (!opened)
            {
                // a creature standing on the bag makes the server say 'Sorry, not possible': one more try when it has moved
                Pump(1500, () => false);
                var again = FindLootOn(at);
                if (again != null) { (tile, stack, cid) = again.Value; s.UseItem(tile, (ushort)cid, (byte)stack); opened = WaitFor(3000, () => Seen(0x6E) > opened0); }
            }
            if (!opened)
                return "using the loot container (client id " + cid + ", server id " + sid + ", stack position " + stack + " of tile " + P(tile) + ", the character at " + P(me.Pos) + ", things on the tile [" + string.Join(" ", (world.Get(tile)?.Things ?? new List<Thing>()).Select(th => th.IsCreature ? "c" + th.Creature.Id : th.Item.Id.ToString(CultureInfo.InvariantCulture))) + "]) opened nothing (no 0x6E); server said [" + string.Join(" | ", me.ServerTexts(say0).Take(2)) + "]";
            Pump(400, () => false);
            var ct = p.Containers.Values.FirstOrDefault(c => c.ItemId == cid) ?? p.Containers.Values.LastOrDefault();
            if (ct == null) return "the loot container (client id " + cid + ") opened (0x6E) and no container is open a moment later (closed again by the server, 0x6F)";
            var items = ct.Items.Where(i => i != null).ToList();
            r.Note("loot container: client id " + cid + " (server id " + sid + (wasBag ? ", the loot bag of O435" : ", the monster's own body: this engine has no loot bag patch") + "), name '" + ct.Name + "', capacity " + ct.Capacity + ", " + items.Count + " item(s) [" + string.Join(", ", items.Select(i => i.Id + "x" + Math.Max(1, i.Count))) + "], packets +" + PacketDiff(p, packets0) + "; open containers now [" + string.Join(" ", p.Containers.Values.Select(c => c.Id + ":" + c.ItemId)) + "]");
            if (items.Count == 0) { s.CloseContainer(ct.Id); return ""; }
            // the way a player takes loot: drag each stack onto the backpack slot
            var taken = new List<(int id, int count)>();
            for (int n = 0; n < 4 && ct.Items.Any(i => i != null); n++)
            {
                var it = ct.Items.First(i => i != null);
                int idx = ct.Items.IndexOf(it) + ct.FirstIndex;
                int left0 = ct.Items.Count(i => i != null), count0 = Math.Max(1, it.Count);
                s.MoveItem(GameSession.ContainerPos(ct.Id, idx), (ushort)it.Id, (byte)idx, GameSession.InventoryPos(3), (byte)count0);
                bool gone = WaitFor(2500, () => ct.Items.Count(i => i != null) < left0);
                Pump(250, () => false);
                r.Note("dragged item " + it.Id + "x" + count0 + " onto the backpack slot: " + (gone ? "left the loot container" : "still in the loot container"));
                if (gone) taken.Add((it.Id, count0));
            }
            s.CloseContainer(ct.Id);
            Pump(300, () => false);
            var after = OpenBackpackCounts(bagId);
            if (after == null) return "the backpack did not open again";
            foreach (var (id, count) in taken)
            {
                int was = snap.TryGetValue(id, out int w0) ? w0 : 0, now = after.TryGetValue(id, out int w1) ? w1 : 0;
                r.Note("backpack " + id + ": " + was + " to " + now + " (took " + count + ")");
                if (now >= was + count) moved++;
            }
            if (taken.Count == 0) return "nothing of the " + items.Count + " item(s) in the loot container left it";
            if (moved == 0) return "the " + taken.Count + " stack(s) left the loot container and none showed up in the backpack";
            return "";
        }

        /// <summary>Closes every container, opens the backpack (inventory slot 3) and returns what it holds by client item id (null when it did not open).</summary>
        Dictionary<int, int> OpenBackpackCounts(ushort bagId)
        {
            var p = s.Parser;
            foreach (var oc in p.Containers.Keys.ToList()) s.CloseContainer(oc);
            Pump(300, () => false);
            int o0 = Seen(0x6E);
            s.UseItem(GameSession.InventoryPos(3), bagId, 0);
            if (!WaitFor(3000, () => Seen(0x6E) > o0 && p.Containers.Count > 0)) return null;
            Pump(300, () => false);
            var d = new Dictionary<int, int>();
            foreach (var c in p.Containers.Values) foreach (var it in c.Items) if (it != null) d[it.Id] = (d.TryGetValue(it.Id, out int n) ? n : 0) + Math.Max(1, it.Count);
            return d;
        }

        /// <summary>The first honest kill: a weak monster (--weak, default Rat) in the first hunt, killed with the class's first attack spell and its normal attack, the loot read and taken,
        /// experience gained, and a level up and its unlock pushes when the experience reaches one. Needs a character in town; skips when none of the grounds can be reached.</summary>
        void ScFirstKill(ScenarioResult r)
        {
            var p = s.Parser;
            if (p.Level > 150) { r.Skip("character level " + p.Level + ": the first hour scenarios are for a new character (the weak monsters give no experience at this level); run them on a character made for the run"); return; }
            if (floorChanges == null) { r.Skip("no items.xml: the stairs down to the first hunt come from it (--items-xml, or the file beside items.otb)"); return; }
            string weak = string.IsNullOrEmpty(o.Weak) ? "Rat" : o.Weak;
            var problems = new StringBuilder();
            var mark = Mark.Of(me);
            if (!s.Spells.Loaded) { s.Spells.Open(); WaitFor(5000, () => s.Spells.Loaded); }
            var spell = s.Spells.Loaded ? s.Spells.Visible(SpellBook.FilterLearned, "attack", "").OrderBy(x => x.Level).ThenBy(x => x.Mana).FirstOrDefault() : null;
            r.Note("character level " + p.Level + ", health " + p.Health + "/" + p.MaxHealth + ", mana " + p.Mana + "/" + p.MaxMana + ", at " + P(me.Pos) + "; first attack spell: " + (spell == null ? "none (melee only)" : spell.Name + " '" + spell.Words + "' L" + spell.Level + " " + spell.Mana + "mp, group " + spell.Group + ", cooldown " + spell.Cooldown + " ms, range " + spell.Range));
            s.SetFightModes(new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = true });
            Pump(300, () => false);
            var target = ReachMonster(r, weak, problems);
            if (target == null)
            {
                string tex = problems.ToString().Trim();
                r.Skip("no " + weak + " in view after going down and walking to the known grounds (at " + P(me.Pos) + ")" + (tex.Length > 0 ? ": " + tex : ""));
                return;
            }
            int maxKills = 24;
            bool looted = false, anyKill = false, everBag = false;
            int kills = 0, deaths = 0, emptyReads = 0;
            var lootFails = new List<string>();
            long expStart = (long)p.Experience;
            int levelStart = p.Level;
            for (int k = 0; k < maxKills && !looted && s.Closed == null; k++)
            {
                if (target == null || !world.Creatures.ContainsKey(target.Id)) target = NearestMonster(me, weak, true);
                if (target == null)
                {
                    foreach (var g in RatGrounds.Where(g => g.Z == me.Pos.Z)) { WalkTo(me, g, 3, 30000, false, out _); target = NearestMonster(me, weak, true); if (target != null) break; }
                    if (target == null) { r.Note("no further " + weak + " in view at " + P(me.Pos)); break; }
                }
                var log = FightOne(target, spell, 40000);
                r.Note("fight " + (k + 1) + ": " + target.Name + " at " + P(log.LastPos) + " " + (log.Died ? "the character died" : log.Killed ? "killed" : log.Gone ? "left the map without an experience text" : "still alive at the time limit") + " in " + (log.Ms / 1000).ToString("0.0", CultureInfo.InvariantCulture) + " s, " + log.Attacks + " attack order(s), " + log.Casts + " cast(s), lowest health " + (log.HealthMin == int.MaxValue ? p.Health : log.HealthMin) + ", experience " + log.ExpBefore + " to " + log.ExpAfter + " (text +" + log.Gain + ", " + log.ExpTexts + " text(s), 0xA0 +" + log.StatsPackets + ")" + (log.Lines.Count > 0 ? ", server [" + string.Join(" | ", log.Lines) + "]" : ""));
                if (log.Died) { deaths++; problems.Append("the character died fighting a " + weak + "; "); break; }
                target = null;
                if (!log.Killed) { if (log.Gone) problems.Append("the " + weak + " left the map and no experience text came; "); continue; }
                anyKill = true;
                kills++;
                if (log.ExpAfter <= log.ExpBefore) problems.Append("the kill gave no experience in 0xA0 (" + log.ExpBefore + " to " + log.ExpAfter + "); ");
                if (log.StatsPackets == 0) problems.Append("no 0xA0 stats packet after the kill; ");
                string lootProblem = LootKill(r, log.LastPos, out int moved, out bool wasBag);
                everBag |= wasBag;
                if (lootProblem.Length > 0) { lootFails.Add(lootProblem); r.Note("loot attempt failed: " + lootProblem); continue; }
                looted = moved > 0;
                if (!looted) { emptyReads++; r.Note("the loot container was empty; killing another"); }
            }
            long expEnd = (long)p.Experience;
            r.Note("after " + kills + " kill(s): experience " + expStart + " to " + expEnd + ", level " + levelStart + " to " + p.Level + ", health " + p.Health + "/" + p.MaxHealth + ", looted " + looted);
            if (p.Level > levelStart)
            {
                r.Note("level up " + levelStart + " to " + p.Level + ": server lines [" + string.Join(" | ", me.ServerTexts(0).Where(x => x.IndexOf("advanced", StringComparison.OrdinalIgnoreCase) >= 0).TakeLast(2)) + "]; 0xA0 and spell pushes read, spells ready " + (s.Spells.Loaded ? s.Spells.Visible(SpellBook.FilterLearned, "all", "").Count : 0));
            }
            else r.Note("no level up: " + (expEnd - expStart) + " experience gained in " + kills + " kill(s) (the next level needs more)");
            // an empty body is the server's rule, not a client fault: every coin of a kill goes to the bank (autoloot.lua ChaosAutolootGold.wanted, owner 2026-10-21) and a
            // Cave Rat's other drops are rare, so CI saw 2 to 7 empty bodies in a row (PR 325). Reading an empty container is enough; taking items is checked when there are any.
            if (!looted && anyKill && emptyReads > 0) r.Note("no item to take in " + emptyReads + " loot container(s) read: the coins go to the bank and the other drops are rare; the open and read path passed");
            else if (!looted && anyKill) problems.Append("no loot was taken in " + kills + " kill(s)" + (lootFails.Count > 0 ? ": " + string.Join(" | ", lootFails.Take(2)) : " (every loot container was empty)") + "; ");
            problems.Append(mark.Diff(me, "primary"));
            if (!anyKill && problems.Length == 0) problems.Append("no " + weak + " was killed; ");
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass(kills + " " + weak + " killed with " + (spell == null ? "melee" : spell.Name + " and melee") + ", " + (expEnd - expStart) + " experience, loot " + (everBag ? "bag" : "container") + " opened and read" + (looted ? ", items taken into the backpack" : " (" + emptyReads + " empty: coins go to the bank)") + ", no parse failure");
        }
        // ------------------------------------------------------------------------------------ firstquest
        /// <summary>Cinderhold's temple spot, the great purple teleport north-west of it (its tiles lead to the teleport room, x 32364-32366, y 32235-32236) and the cellar the first tale
        /// sends the player to (tales_config.lua cellar_teeth: visit 32378,32226,8 within 8 tiles, kill 25 Rat or Cave Rat, report to Archivist Maelis).</summary>
        static readonly Pos TempleSpot = new Pos(32369, 32241, 7), HubPortal = new Pos(32365, 32235, 7), CellarVisit = new Pos(32378, 32226, 8), HubArchivist = new Pos(31672, 32236, 7);
        const string TaleName = "Teeth in the Cellars";

        bool NearTemple() => me.Pos.Z == TempleSpot.Z && PathFinder.Cheb(me.Pos, TempleSpot) <= 14;
        bool InHub() => me.Pos.Z == 7 && me.Pos.X < 31900;

        /// <summary>Uses the temple teleport scroll of the starter kit (server item 6119): the way back to the temple a new player has from the first hour. Retries every 6 s while the
        /// server refuses (not usable in a fight). True when the character moved far from where it stood.</summary>
        bool UseTempleScroll(ScenarioResult r, int limitMs)
        {
            var p = s.Parser;
            if (serverToClient == null || !serverToClient.TryGetValue(6119, out int scrollCid)) { r.Note("no items.otb node for the temple scroll (server id 6119)"); return false; }
            if (p.Inventory.Length <= 3 || p.Inventory[3] == null) return false;
            long end = Tick + limitMs;
            while (Tick < end && s.Closed == null && !p.Dead)
            {
                // the server refuses the scroll in a fight: whatever stands next to the character is dealt with first, like a player would
                var near = NearestMonster(me, null, true);
                if (near != null && PathFinder.Cheb(near.Position, me.Pos) <= 3)
                {
                    var spell = s.Spells.Loaded ? s.Spells.Visible(SpellBook.FilterLearned, "attack", "").OrderBy(x => x.Level).ThenBy(x => x.Mana).FirstOrDefault() : null;
                    FightOne(near, spell, 20000);
                    continue;
                }
                if (OpenBackpackCounts((ushort)p.Inventory[3].Id) == null) return false;
                int slot = -1;
                byte contId = 0;
                foreach (var ct in p.Containers.Values)
                {
                    int i = ct.Items.FindIndex(it => it != null && it.Id == scrollCid);
                    if (i >= 0) { slot = i + ct.FirstIndex; contId = ct.Id; break; }
                }
                if (slot < 0) { r.Note("no temple scroll in the backpack (client id " + scrollCid + ")"); return false; }
                var from = me.Pos;
                int say0 = me.Said.Count;
                s.UseItem(GameSession.ContainerPos(contId, slot), (ushort)scrollCid, (byte)slot);
                bool moved = WaitFor(6000, () => PathFinder.Cheb(me.Pos, from) > 10 || me.Pos.Z != from.Z);
                Pump(1500, () => false);
                r.Note("temple scroll used at " + P(from) + ": " + (moved ? "now at " + P(me.Pos) : "no move") + ", server said [" + string.Join(" | ", me.ServerTexts(say0).Take(2)) + "]");
                if (moved) return true;
                Pump(6000, () => false);
            }
            return false;
        }

        /// <summary>The great purple teleport: walks beside its tile and steps on it. True when the character arrived far away, in the teleport room.</summary>
        bool EnterHub(ScenarioResult r, StringBuilder problems)
        {
            avoidStairs = true;
            try
            {
                if (!WalkTo(me, HubPortal, 2, 40000, false, out string why)) { problems.Append("could not walk to the great purple teleport at " + P(HubPortal) + ": " + why + "; "); return false; }
                var cands = world.Tiles.Where(kv => kv.Key.Z == me.Pos.Z && PathFinder.Cheb(kv.Key, HubPortal) <= 3 && kv.Value.Things.Any(th => !th.IsCreature && th.Item != null && teleportClient.Contains(th.Item.Id))).Select(kv => kv.Key).OrderBy(k => PathFinder.Cheb(k, HubPortal)).ToList();
                r.Note("teleport tiles near the portal: " + (cands.Count == 0 ? "none known" : string.Join(" ", cands.Select(P))));
                foreach (var tile in cands)
                {
                    var from = me.Pos;
                    if (!WalkTo(me, tile, 1, 20000, false, out string why2)) { r.Note("no way beside the teleport tile " + P(tile) + ": " + why2); continue; }
                    Dir? dir = null;
                    foreach (var d in WalkDirs.All) if (WalkDirs.Step(me.Pos, d).Equals(tile)) dir = d;
                    if (dir == null) continue;
                    if (!WaitFor(3000, () => s.CanWalk)) continue;
                    s.Walk(dir.Value);
                    bool jumped = WaitFor(5000, () => PathFinder.Cheb(me.Pos, from) > 20);
                    Pump(1500, () => false);
                    r.Note("stepped on the teleport tile " + P(tile) + ": " + (jumped ? "arrived at " + P(me.Pos) : "no jump (at " + P(me.Pos) + ")"));
                    if (jumped) return true;
                }
                problems.Append("no teleport tile of the great purple teleport took the character away from the temple; ");
                return false;
            }
            finally { avoidStairs = false; }
        }

        /// <summary>The Archivist's list of tales: walks to her stall, says hi and tales, and returns the list window.</summary>
        ModalWindowData OpenTales(ScenarioResult r, StringBuilder problems)
        {
            var p = s.Parser;
            var npc = FindNpc("Archivist Maelis");
            if (npc == null)
            {
                WalkTo(me, HubArchivist, 2, 60000, false, out string approach);
                r.Note("approach to the market stalls at " + P(HubArchivist) + ": " + (approach.Length == 0 ? "arrived" : approach));
                npc = FindNpc("Archivist Maelis");
            }
            if (npc == null) { problems.Append("Archivist Maelis is not in view of " + P(me.Pos) + "; "); return null; }
            if (!WalkTo(me, npc.Position, 2, 40000, false, out string why) && (PathFinder.Cheb(me.Pos, npc.Position) > 3 || me.Pos.Z != npc.Position.Z)) { problems.Append("could not walk to the Archivist: " + why + "; "); return null; }
            Pump(500, () => false);
            int old = 0;
            while (p.Modals.Current != null && old < 6) { p.Modals.Cancel(); old++; Pump(300, () => false); }
            int lines0 = p.NpcTalk.Lines.Count;
            s.SayToNpc("hi");
            if (!WaitFor(6000, () => p.NpcTalk.Lines.Skip(lines0).Any(l => l.FromNpc))) { problems.Append("the Archivist did not answer 'hi'; "); return null; }
            int recv0 = p.Modals.Received;
            s.SayToNpc("tales");
            if (!WaitFor(6000, () => p.Modals.Received > recv0)) { problems.Append("'tales' brought no list window; the Archivist said: " + string.Join(" | ", p.NpcTalk.Lines.Skip(lines0).Where(l => l.FromNpc).Select(l => l.Text).Take(2)) + "; "); return null; }
            Pump(300, () => false);
            return p.Modals.Current;
        }

        /// <summary>Picks the Teeth in the Cellars entry in the open list, presses its first button (Read) and returns the tale window.</summary>
        ModalWindowData ReadTale(ScenarioResult r, ModalWindowData list, StringBuilder problems)
        {
            var p = s.Parser;
            var entry = list.Choices.FirstOrDefault(c => c.Text.IndexOf(TaleName, StringComparison.OrdinalIgnoreCase) >= 0);
            if (entry == null) { problems.Append("the list of tales does not offer '" + TaleName + "' (" + list.Choices.Count + " entries: " + string.Join(", ", list.Choices.Take(6).Select(c => c.Text)) + "); "); return null; }
            int recv = p.Modals.Received;
            p.Modals.Answer(list.Buttons.Count > 0 ? list.Buttons[0].Id : 1, entry.Id);
            if (!WaitFor(6000, () => p.Modals.Received > recv)) { problems.Append("reading the tale brought no window; "); return null; }
            Pump(300, () => false);
            return p.Modals.Current;
        }

        /// <summary>The numbers of "Teeth in the Cellars: N / 25." lines since line `from`: the last count seen.</summary>
        int TaleProgress(int from, out int of)
        {
            int n = -1;
            of = 0;
            foreach (string t in me.ServerTexts(from))
            {
                int i = t.IndexOf(TaleName + ": ", StringComparison.Ordinal);
                if (i < 0) continue;
                var m = System.Text.RegularExpressions.Regex.Match(t.Substring(i + TaleName.Length + 2), @"^(\d+) / (\d+)");
                if (m.Success) { n = int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture); of = int.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture); }
            }
            return n;
        }

        /// <summary>Walks to `goal` (within `range`) and kills the Rats that come, or, without a goal, roams the cave and kills Rats until `stop` says so. Returns the kills.</summary>
        int RoamAndKill(ScenarioResult r, Spell spell, Pos? goal, int range, long limitMs, Func<bool> stop, StringBuilder problems)
        {
            var p = s.Parser;
            long end = Tick + limitMs;
            int kills = 0, gi = 0, idle = 0;
            avoidStairs = true;
            try
            {
                while (Tick < end && !stop() && s.Closed == null)
                {
                    if (p.Dead) { problems.Append("the character died in the cellars; "); break; }
                    var t = NearestMonster(me, "Rat", true);
                    if (t != null && PathFinder.Cheb(t.Position, me.Pos) <= (goal.HasValue ? 2 : 10))
                    {
                        var log = FightOne(t, spell, 30000);
                        if (log.Killed) kills++;
                        if (log.Died) { problems.Append("the character died in the cellars; "); break; }
                        continue;
                    }
                    Pos aim;
                    if (goal.HasValue) aim = goal.Value;
                    else
                    {
                        var all = RatGrounds.Where(g => g.Z == me.Pos.Z).ToArray();
                        if (all.Length == 0) break;
                        aim = all[gi++ % all.Length];
                    }
                    if (aim.Z != me.Pos.Z) { problems.Append("the goal " + P(aim) + " is on another floor than the character (" + P(me.Pos) + "); "); break; }
                    bool ok = WalkTo(me, aim, goal.HasValue ? range : 3, 12000, false, out string why);
                    if (!ok)
                    {
                        // the way is blocked: by the rats themselves (a creature counts as a wall for the path), so the nearest one is fought where it stands
                        var blocker = NearestMonster(me, "Rat", false);
                        if (blocker != null && PathFinder.Cheb(blocker.Position, me.Pos) <= 12)
                        {
                            var log = FightOne(blocker, spell, 30000);
                            if (log.Killed) kills++;
                            if (log.Died) { problems.Append("the character died in the cellars; "); break; }
                            idle = 0;
                            continue;
                        }
                        idle++;
                        Pump(800, () => false);
                        if (goal.HasValue && idle > 6) { r.Note("no way towards " + P(aim) + " from " + P(me.Pos) + ": " + why); break; }
                    }
                    else idle = 0;
                    if (!goal.HasValue && ok) Pump(600, () => false);
                }
            }
            finally { avoidStairs = false; }
            return kills;
        }

        /// <summary>The first tale of a new player, start to end: the great purple teleport to the market of the teleport room, Archivist Maelis (hi, tales, the list window, Teeth in the
        /// Cellars, Read, Accept), the temple scroll back, down to the cellars (the visit step), 25 rats (the progress lines), back to the Archivist (Turn in): the reward, the level up with
        /// its 0xA0 push and the spell unlock pushes, the quest log (0xF0, 0xF1) before and after. Skips with the reason when a step needs what the map lacks.</summary>
        void ScFirstQuest(ScenarioResult r)
        {
            var p = s.Parser;
            if (p.Level > 150) { r.Skip("character level " + p.Level + ": the first hour scenarios are for a new character; run them on a character made for the run"); return; }
            if (floorChanges == null || serverToClient == null) { r.Skip("no items.otb or items.xml: the stairs, the teleport and the scroll come from them"); return; }
            var problems = new StringBuilder();
            var mark = Mark.Of(me);
            int bad0 = ExtBad();
            if (!s.Spells.Loaded) { s.Spells.Open(); WaitFor(5000, () => s.Spells.Loaded); }
            var spell = s.Spells.Loaded ? s.Spells.Visible(SpellBook.FilterLearned, "attack", "").OrderBy(x => x.Level).ThenBy(x => x.Mana).FirstOrDefault() : null;
            s.SetFightModes(new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = true });
            int levelStart = p.Level;
            long expStart = (long)p.Experience;
            var seen228 = new Dictionary<byte, int>();
            foreach (byte op in new byte[] { 79, 115, 153, 178 }) seen228[op] = ops.TryGetValue(op, out var st0) ? st0.Replies : 0;
            r.Note("character level " + p.Level + " at " + P(me.Pos) + ", experience " + expStart + ", health " + p.Health + "/" + p.MaxHealth);
            QuestLogPart(r, "quest log before the tale");

            // ---- to the temple and the teleport room
            if (!NearTemple() && !InHub())
            {
                // a character left in the cellars (after firstkill) climbs out by the ladder first: the rats there keep it in combat, and the server refuses the scroll in a fight
                if (me.Pos.Z == 8) { var up = new StringBuilder(); GoUp(r, up, "out of the cave"); Pump(800, () => false); if (up.Length > 0) r.Note(up.ToString().Trim()); }
                if (!NearTemple() && !InHub() && !UseTempleScroll(r, 120000)) { r.Skip("the character is at " + P(me.Pos) + ", far from Cinderhold's temple, and the temple scroll did not bring it back"); return; }
            }
            if (!InHub())
            {
                if (!NearTemple()) { r.Skip("the character is at " + P(me.Pos) + ", not in Cinderhold"); return; }
                if (!EnterHub(r, problems)) { r.Fail(problems.ToString().Trim()); return; }
            }
            if (!InHub()) { r.Fail("not in the teleport room after the great purple teleport (at " + P(me.Pos) + ")"); return; }

            // ---- the Archivist: hi, tales, the list, the tale, Accept
            var list = OpenTales(r, problems);
            if (list == null) { r.Fail(problems.ToString().Trim()); return; }
            r.Note("list window (id " + list.Id + "): " + ModalLine(list));
            if (list.Id != 7170) r.Note("the list window id is " + list.Id + ", tales_config.lua modal.list is 7170");
            var tale = ReadTale(r, list, problems);
            if (tale == null) { s.SayToNpc("bye"); r.Fail(problems.ToString().Trim()); return; }
            r.Note("tale window (id " + tale.Id + "): " + ModalLine(tale));
            // a tale that stands ready to turn in (an earlier run did the rest) goes straight to the turn-in
            bool readyAtStart = tale.Buttons.Any(b => b.Id == 3);
            int progress = 0, total = 0;
            if (readyAtStart) r.Note("the tale window offers Turn in at once: the tale was done by an earlier run on this character, the run goes to the turn-in");
            if (!readyAtStart)
            {
                var accept = tale.Buttons.FirstOrDefault(b => b.Id == 1);
                int say0 = me.Said.Count, recv0 = p.Modals.Received;
                bool accepted;
                if (accept == null)
                {
                    // taken by an earlier run on this character: the window offers no Accept, the tale goes on from where it stands
                    accepted = tale.Buttons.Any(b => b.Id == 3) || tale.Message.IndexOf("in progress", StringComparison.OrdinalIgnoreCase) >= 0 || tale.Message.IndexOf("Steps", StringComparison.OrdinalIgnoreCase) >= 0;
                    r.Note("the tale window has no Accept button (buttons: " + string.Join(", ", tale.Buttons.Select(b => b.Id + "=" + b.Text)) + "): the tale was taken before, the run goes on from its state");
                }
                else
                {
                    p.Modals.Answer(accept.Id, ModalWindows.NoChoice);
                    accepted = WaitFor(6000, () => me.ServerTexts(say0).Any(t => t.IndexOf("Tale accepted", StringComparison.OrdinalIgnoreCase) >= 0));
                    Pump(1500, () => false);
                    r.Note("Accept answered: server said [" + string.Join(" | ", me.ServerTexts(say0).Take(3)) + "]; windows +" + (p.Modals.Received - recv0));
                }
                if (!accepted) problems.Append("Accept brought no 'Tale accepted' line; ");
                p.Modals.Clear();
                s.SayToNpc("bye");
                Pump(500, () => false);
                r.Note("pushes since the start: " + string.Join(", ", seen228.Select(kv => kv.Key + " +" + ((ops.TryGetValue(kv.Key, out var st1) ? st1.Replies : 0) - kv.Value))) + "; opcode 153 actions [" + string.Join(",", ops[153].Actions) + "], 178 [" + string.Join(",", ops[178].Actions) + "]");
                QuestLogPart(r, "quest log after Accept");
                if (!accepted) { r.Fail(problems.ToString().Trim()); return; }

                // ---- back to the temple (the scroll), down to the cellars, the visit step
                int say1 = me.Said.Count;
                if (!UseTempleScroll(r, 20000)) { r.Fail(problems.Append("the temple scroll did not bring the character back from the teleport room; ").ToString().Trim()); return; }
                if (!GoDown(r, problems, CellarRoute, CellarStair, "cellar stair")) { r.Skip("the cellar stair of the tale could not be reached: " + problems.ToString().Trim()); return; }
                Pump(1500, () => false);
                // the visit counts within 8 tiles of the mark, checked every 3 s by the server
                RoamAndKill(r, spell, CellarVisit, 6, 60000, () => me.ServerTexts(say1).Any(t => t.IndexOf(TaleName, StringComparison.Ordinal) >= 0 && t.IndexOf("step done", StringComparison.OrdinalIgnoreCase) >= 0), problems);
                Pump(3500, () => me.ServerTexts(say1).Any(t => t.IndexOf("step done", StringComparison.OrdinalIgnoreCase) >= 0));
                bool visited = me.ServerTexts(say1).Any(t => t.IndexOf(TaleName, StringComparison.Ordinal) >= 0 && t.IndexOf("step done", StringComparison.OrdinalIgnoreCase) >= 0);
                r.Note("visit step: " + (visited ? "done" : "not done") + " at " + P(me.Pos) + " (the mark is " + P(CellarVisit) + ", radius 8); server [" + string.Join(" | ", me.ServerTexts(say1).Where(t => t.IndexOf(TaleName, StringComparison.Ordinal) >= 0).Take(3)) + "]");
                if (!visited) { r.Skip("the visit step of the tale was not reached from the cellar stair (the character is at " + P(me.Pos) + ", the mark at " + P(CellarVisit) + "): " + problems.ToString().Trim()); return; }
                // up again and to the stair of the cave where the rats are
                if (!GoUp(r, problems, "back up")) { r.Fail(problems.ToString().Trim()); return; }
                Pump(1200, () => false);
                if (!GoDown(r, problems, RatRouteFromCellar, DescentStair, "rat stair")) { r.Skip("the rat cave could not be reached from the cellar: " + problems.ToString().Trim()); return; }
                Pump(1200, () => false);

                // ---- the 25 rats
                int say2 = me.Said.Count;
                long expKills0 = (long)p.Experience;
                RoamAndKill(r, spell, null, 0, 900000, () => { int pr = TaleProgress(say2, out int of); return of > 0 && pr >= of || me.ServerTexts(say2).Any(t => t.IndexOf("Return to the Archivist", StringComparison.OrdinalIgnoreCase) >= 0); }, problems);
                Pump(1500, () => false);
                progress = TaleProgress(say2, out total);
                var stepLines = me.ServerTexts(say2).Where(t => t.IndexOf(TaleName, StringComparison.Ordinal) >= 0).ToList();
                bool ready = stepLines.Any(t => t.IndexOf("Return to the Archivist", StringComparison.OrdinalIgnoreCase) >= 0);
                r.Note("kill step: " + progress + " of " + total + " counted, ready to turn in " + ready + ", " + stepLines.Count + " progress line(s) [first " + (stepLines.Count > 0 ? stepLines[0] : "none") + ", last " + (stepLines.Count > 0 ? stepLines[stepLines.Count - 1] : "none") + "], experience " + expKills0 + " to " + (long)p.Experience + ", level " + p.Level);
                if (!ready) { r.Skip("only " + progress + " of " + total + " rats were killed in the time limit (the cellar spawns did not give 25): " + problems.ToString().Trim()); return; }

                // ---- the way back to the Archivist: out of the cave by its ladder (the rats keep the character in combat down there), the scroll, the great purple teleport, the turn-in
                if (me.Pos.Z != TempleSpot.Z && !GoUp(r, problems, "out of the cave")) { r.Fail(problems.ToString().Trim()); return; }
                Pump(800, () => false);
                if (!UseTempleScroll(r, 150000)) { r.Fail(problems.Append("the temple scroll did not bring the character back from the cellars; ").ToString().Trim()); return; }
                if (!EnterHub(r, problems)) { r.Fail(problems.ToString().Trim()); return; }
                list = OpenTales(r, problems);
                if (list == null) { r.Fail(problems.ToString().Trim()); return; }
                tale = ReadTale(r, list, problems);
                if (tale == null) { s.SayToNpc("bye"); r.Fail(problems.ToString().Trim()); return; }
                r.Note("tale window before the turn-in: " + ModalLine(tale));
            }
            var turnIn = tale.Buttons.FirstOrDefault(b => b.Id == 3);
            if (turnIn == null) { r.Fail("the tale window has no Turn in button (buttons: " + string.Join(", ", tale.Buttons.Select(b => b.Id + "=" + b.Text)) + ")"); return; }
            int say3 = me.Said.Count, lvl0 = p.Level, a0 = Seen(0xA0), d115 = ops.TryGetValue(115, out var s115) ? s115.Replies : 0;
            long expTurn0 = (long)p.Experience;
            var spellsBefore = s.Spells.Loaded ? s.Spells.Visible(SpellBook.FilterLearned, "all", "").Count : 0;
            p.Modals.Answer(turnIn.Id, ModalWindows.NoChoice);
            bool done = WaitFor(8000, () => me.ServerTexts(say3).Any(t => t.IndexOf("Tale complete", StringComparison.OrdinalIgnoreCase) >= 0));
            Pump(2500, () => false);
            var rewardLines = me.ServerTexts(say3).ToList();
            r.Note("Turn in answered: [" + string.Join(" | ", rewardLines.Take(6).Select(t => t.Length > 140 ? t.Substring(0, 140) + "..." : t)) + "]");
            r.Note("reward: experience " + expTurn0 + " to " + (long)p.Experience + ", level " + lvl0 + " to " + p.Level + ", 0xA0 +" + (Seen(0xA0) - a0) + ", unlock pushes (115) +" + ((ops.TryGetValue(115, out var s115b) ? s115b.Replies : 0) - d115));
            if (!done) problems.Append("Turn in brought no 'Tale complete' line; ");
            else
            {
                if ((long)p.Experience <= expTurn0) problems.Append("the turn-in gave no experience (0xA0 " + expTurn0 + " to " + (long)p.Experience + "); ");
                if (Seen(0xA0) == a0) problems.Append("no 0xA0 stats packet after the turn-in; ");
            }
            if (p.Level > lvl0)
            {
                if (!rewardLines.Any(t => t.IndexOf("advanced from Level", StringComparison.OrdinalIgnoreCase) >= 0)) problems.Append("the level rose and no 'You advanced from Level' line came; ");
                var learned = s.Spells.Loaded ? s.Spells.Visible(SpellBook.FilterLearned, "all", "").Count : 0;
                r.Note("level up " + lvl0 + " to " + p.Level + ": spells ready " + spellsBefore + " to " + learned + " (the spell list is refreshed after a level)");
            }
            else r.Note("the turn-in gave no level (a full level of experience is the reward share 1.0 of the next level; the bonus may fall short)");
            QuestLogPart(r, "quest log after the turn-in");
            p.Modals.Clear();
            s.SayToNpc("bye");
            Pump(500, () => false);
            if (ExtBad() > bad0) problems.Append((ExtBad() - bad0) + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("tale '" + TaleName + "' " + (readyAtStart ? "(taken, visited and killed for by an earlier run) " : "taken at the Archivist, visited, " + progress + " of " + total + " rats killed, ") + "turned in: experience " + expStart + " to " + (long)p.Experience + ", level " + levelStart + " to " + p.Level + ", the quest log read before and after, no parse failure");
        }

        /// <summary>Asks the base quest log (0xF0) and the first quest's mission lines (0xF1) and notes what came.</summary>
        void QuestLogPart(ScenarioResult r, string label)
        {
            var p = s.Parser;
            int n0 = Seen(0xF0);
            p.Quests.Request();
            bool got = WaitFor(3000, () => Seen(0xF0) > n0);
            string names = string.Join(", ", p.Quests.Quests.Take(4).Select(q => q.Name + (q.Completed ? " (done)" : "")));
            string lines = "";
            var first = p.Quests.Quests.FirstOrDefault(q => !q.Completed) ?? p.Quests.Quests.FirstOrDefault();
            if (got && first != null)
            {
                int l0 = Seen(0xF1);
                p.Quests.Select(first.Id);
                bool gotLine = WaitFor(3000, () => Seen(0xF1) > l0);
                var m = p.Quests.Missions(first.Id);
                lines = "; mission lines of '" + first.Name + "': " + (gotLine && m != null ? m.Count.ToString(CultureInfo.InvariantCulture) : "no answer");
            }
            r.Note(label + ": 0xF0 " + (got ? "answered" : "no answer") + ", " + p.Quests.Quests.Count + " quest(s), " + p.Quests.Done() + " done [" + names + "]" + lines);
        }
        /// <summary>One exploring walk of a client in a place it does not know (a rift): the nearest known walkable tile that has an unknown neighbour (and was not tried), reached over the
        /// tiles in view. A player in a rift does the same: goes on until the monsters are there. Returns false when no frontier is left.</summary>
        bool ExploreStep(LiveClient a, HashSet<Pos> tried)
        {
            var world = a.World;
            uint id = world.PlayerId;
            var here = a.Pos;
            var seen = new HashSet<Pos> { here };
            var queue = new Queue<Pos>();
            queue.Enqueue(here);
            Pos? best = null;
            int bestScore = int.MinValue;
            while (queue.Count > 0)
            {
                var cur = queue.Dequeue();
                if (PathFinder.Cheb(cur, here) >= 3 && !tried.Contains(cur))
                {
                    bool frontier = false;
                    foreach (var d in WalkDirs.All) if (world.Get(WalkDirs.Step(cur, d)) == null) { frontier = true; break; }
                    if (frontier)
                    {
                        int score = PathFinder.Cheb(cur, here) * -1 + PathFinder.Cheb(cur, rift0Entry) / 4;
                        if (score > bestScore) { bestScore = score; best = cur; }
                    }
                }
                foreach (var d in WalkDirs.All)
                {
                    var n = WalkDirs.Step(cur, d);
                    if (seen.Contains(n) || !Passable(world, n, id) || FloorChangeOf(world.Get(n)) != null) continue;
                    seen.Add(n);
                    queue.Enqueue(n);
                }
            }
            if (best == null) return false;
            tried.Add(best.Value);
            WalkTo(a, best.Value, 0, 8000, false, out _);
            return true;
        }

        /// <summary>Where the explorer began (the rift's entrance): it prefers frontiers away from it.</summary>
        Pos rift0Entry;

        // ------------------------------------------------------------------------------------ riftkilled
        /// <summary>The honest rift death: a mortal character (the second account, no staff right) opens a rift alone and is killed by the rift's own monsters, no /rdie, no /rcalm, no
        /// staff kill. It fights back like a player (attack on the nearest monster every 3 s) and keeps dying until the shared lives are gone. Each death: 0x28 once, the HUD's end
        /// message `left` with the lives left (the same HUD and death flow as riftsolodeath), the next login back at the entrance with the HUD running; the last one: `failed`, the
        /// next login at the temple with no HUD and no key back. A character that survives the time limit makes it a skip (the local db gave it little health to make a death
        /// quick: unity/README.md "A new player's first hour (phase 27)"). The key comes from the local helper /rgive (a mortal has no /rift key).</summary>
        void ScRiftKilled(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) { r.Skip(err); return; }
            if (serverToClient == null) { r.Skip("no items.otb: the rift key comes from it"); return; }
            if (partner.S.Party.InParty) LeaveWithRetry(partner, new[] { me }, 20000, out _);
            var markA = Mark.Of(me);
            var markB = Mark.Of(partner);
            var problems = new StringBuilder();
            int primary228 = ops[228].Replies;
            Pos home = partner.Pos;
            string mods = string.IsNullOrEmpty(o.RiftMods) ? "vitality:20" : o.RiftMods;
            int bad0 = ExtBad();
            bool done = false;
            Pos before = home;
            int deaths = 0;
            long deathLimitMs = Math.Max(90000, o.ScenarioMs);
            try
            {
                if (!OpenRiftAs(partner, r, 1, mods, false, out before)) return;
                var hud = partner.S.Progress.Rift;
                var pp = partner.S.Parser;
                var entry = partner.Pos;
                int lives0 = hud.Lives;
                r.Note("opened alone by the mortal character: " + HudLine(hud) + ", at " + P(entry) + ", health " + pp.Health + "/" + pp.MaxHealth + ", level " + pp.Level + ", no staff command is used from here on");
                if (lives0 < 1) problems.Append("a solo rift starts with " + lives0 + " life/lives; ");
                for (int round = 0; round <= lives0 + 1 && partner != null && partner.S.Closed == null; round++)
                {
                    // the partner fights the nearest monster of the rift like a player until it dies
                    int d0 = SeenOf(partner, 0x28), t0 = partner.Said.Count;
                    var seenDeath = new Dictionary<byte, int>(pp.Seen);
                    long start = Tick, nextAttack = 0;
                    int hits = 0;
                    int hpMin = pp.Health;
                    var tried = new HashSet<Pos>();
                    rift0Entry = partner.Pos;
                    int explored = 0;
                    partner.S.SetFightModes(new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = true });
                    while (!pp.Dead && Tick - start < deathLimitMs && partner.S.Closed == null)
                    {
                        Pump(300, () => pp.Dead);
                        hpMin = Math.Min(hpMin, pp.Health);
                        var m = NearestMonster(partner, null, false);
                        if (m != null && PathFinder.Cheb(m.Position, partner.Pos) <= 12)
                        {
                            if (Tick >= nextAttack) { partner.S.Attack(m.Id); hits++; nextAttack = Tick + 3000; }
                        }
                        else if (!pp.Dead && ExploreStep(partner, tried)) explored++;
                        else if (m == null && tried.Count > 40) tried.Clear();
                    }
                    if (!pp.Dead)
                    {
                        var near = partner.World.Creatures.Values.Where(c => c.Type == 1 && c.Position.X > 0 && c.Position.Z == partner.Pos.Z).Select(c => PathFinder.Cheb(c.Position, partner.Pos)).OrderBy(x => x).Take(5).ToList();
                        if (deaths == 0) { r.Skip("the rift's monsters did not kill the mortal character in " + (deathLimitMs / 1000) + " s (health " + pp.Health + "/" + pp.MaxHealth + ", lowest " + hpMin + ", " + hits + " attack order(s), " + explored + " exploring walk(s), monsters at distance [" + string.Join(",", near) + "]); give the character little health in the local db (README)"); done = false; return; }
                        problems.Append("the character survived round " + (round + 1) + " for " + (deathLimitMs / 1000) + " s (health " + pp.Health + "/" + pp.MaxHealth + "); ");
                        break;
                    }
                    deaths++;
                    Pump(2500, () => false);
                    var lines = LocalFree(partner, t0).Where(t => t.IndexOf("fallen", StringComparison.OrdinalIgnoreCase) >= 0 || t.IndexOf("lives", StringComparison.OrdinalIgnoreCase) >= 0 || t.IndexOf("life", StringComparison.OrdinalIgnoreCase) >= 0 || t.IndexOf("rift", StringComparison.OrdinalIgnoreCase) >= 0 || t.IndexOf("die", StringComparison.OrdinalIgnoreCase) >= 0).Take(4).ToList();
                    bool last = hud.Result == "failed";
                    r.Note("death " + deaths + " after " + ((Tick - start) / 1000.0).ToString("0.0", CultureInfo.InvariantCulture) + " s: 0x28 x" + (SeenOf(partner, 0x28) - d0) + " (type " + pp.DeathType + ", penalty " + pp.DeathPenalty + "%), health lowest " + hpMin + "/" + pp.MaxHealth + ", " + hits + " attack order(s); HUD result '" + hud.Result + "' state '" + hud.State + "' text '" + hud.ResultText + "' lives " + hud.Lives + "/" + hud.LivesMax + "; lines [" + string.Join(" | ", lines) + "]; packets [" + PacketDiff(pp, seenDeath) + "]");
                    if (SeenOf(partner, 0x28) - d0 != 1) problems.Append("0x28 seen " + (SeenOf(partner, 0x28) - d0) + " times on death " + deaths + "; ");
                    if (pp.DeathType != 0 && pp.DeathType != 1) problems.Append("death type " + pp.DeathType + "; ");
                    if (pp.DeathPenalty < 0 || pp.DeathPenalty > 100) problems.Append("death penalty " + pp.DeathPenalty + "; ");
                    if (ops[228].Replies != primary228) problems.Append("the primary, who is not in the rift, got " + (ops[228].Replies - primary228) + " rift message(s); ");
                    if (last)
                    {
                        if (hud.State != "failed") problems.Append("the HUD says state '" + hud.State + "' with result 'failed'; ");
                        if (hud.ResultText.IndexOf("No lives are left", StringComparison.OrdinalIgnoreCase) < 0 || hud.ResultText.IndexOf("key is lost", StringComparison.OrdinalIgnoreCase) < 0) problems.Append("the end text is '" + hud.ResultText + "', expected the lives and the lost key; ");
                        if (hud.Lives != 0) problems.Append("the HUD shows " + hud.Lives + " lives after the last death, expected 0; ");
                        if (deaths != lives0 + 0 && deaths != lives0) r.Note("the rift collapsed after " + deaths + " death(s) with " + lives0 + " lives at the start");
                    }
                    else
                    {
                        if (hud.Result != "left" || hud.State != "left") problems.Append("death " + deaths + ": the HUD says result '" + hud.Result + "' state '" + hud.State + "', expected 'left'; ");
                        int wantLeft = lives0 - deaths;
                        string wantText = wantLeft.ToString(CultureInfo.InvariantCulture) + (wantLeft == 1 ? " life left" : " lives left");
                        if (hud.ResultText.IndexOf(wantText, StringComparison.OrdinalIgnoreCase) < 0) problems.Append("death " + deaths + ": the end text does not name '" + wantText + "' ('" + hud.ResultText + "'); ");
                    }
                    err = ReloginPartner();
                    if (err != null) { problems.Append(err + "; "); break; }
                    hud = partner.S.Progress.Rift;
                    pp = partner.S.Parser;
                    if (last)
                    {
                        Pump(3500, () => false);
                        serverToClient.TryGetValue(o.RiftKeyServerId, out int keyClient);
                        EnsureBagOpen(partner);
                        Pump(600, () => false);
                        int keys = CarriedCount(partner, keyClient);
                        bool step = StepAfterLogin(partner);
                        r.Note("after the last login: at " + P(partner.Pos) + " (town " + P(home) + "), health " + pp.Health + "/" + pp.MaxHealth + ", dead " + pp.Dead + ", rift HUD active " + hud.Active + ", Rift Keys carried " + keys + ", a step " + (step ? "confirmed" : "not confirmed"));
                        if (pp.Dead || pp.Health <= 0) problems.Append("the character came back dead after the last life; ");
                        if (hud.Active) problems.Append("a rift HUD is on after the rift collapsed (state '" + hud.State + "'); ");
                        if (PathFinder.Cheb(partner.Pos, home) > 30 || partner.Pos.Z != home.Z) problems.Append("the character is not back in town after the collapse (at " + P(partner.Pos) + ", town " + P(home) + "); ");
                        if (keys > 0) problems.Append("the lost key came back (" + keys + " Rift Key(s) carried); ");
                        if (!step) problems.Append("the character could not take a step after coming back; ");
                        done = true;
                        break;
                    }
                    WaitFor(6000, () => hud.Active);
                    Pump(1500, () => false);
                    r.Note("after login " + deaths + ": at " + P(partner.Pos) + " (entrance " + P(entry) + "), health " + pp.Health + "/" + pp.MaxHealth + ", dead " + pp.Dead + ", HUD " + (hud.Active ? HudLine(hud) : "none"));
                    if (pp.Dead || pp.Health <= 0) problems.Append("the character came back dead after death " + deaths + "; ");
                    if (PathFinder.Cheb(partner.Pos, entry) > 6 || partner.Pos.Z != entry.Z) problems.Append("the fallen player did not return at the rift's entrance (at " + P(partner.Pos) + ", entrance " + P(entry) + "); ");
                    if (!hud.Active) { problems.Append("the returning player got no rift HUD; "); break; }
                    if (hud.Lives != lives0 - deaths) problems.Append("the returning player's HUD shows " + hud.Lives + " lives, expected " + (lives0 - deaths) + "; ");
                    if (hud.State != "running") problems.Append("the returning player's HUD state is '" + hud.State + "', expected 'running'; ");
                }
                if (!done && problems.Length == 0) problems.Append("the rift did not collapse after " + deaths + " death(s) with " + lives0 + " lives; ");
            }
            finally
            {
                EndRiftOf(partner, before);
                if (partner != null && partner.S.Closed == null && partner.S.Parser.Dead) { string e2 = ReloginPartner(); if (e2 != null) r.Note("login after the death: " + e2); }
                if (partner != null && partner.S.Closed == null && (partner.Pos.Z != me.Pos.Z || PathFinder.Cheb(partner.Pos, me.Pos) > 6))
                {
                    s.Say("/c " + partner.Character);
                    WaitFor(6000, () => partner.Pos.Z == me.Pos.Z && PathFinder.Cheb(partner.Pos, me.Pos) <= 6);
                    Pump(800, () => false);
                }
            }
            if (!done && problems.Length == 0) return;
            if (ExtBad() > bad0) problems.Append((ExtBad() - bad0) + " extended opcode message(s) were invalid JSON or threw in a handler; ");
            problems.Append(markA.Diff(me, "primary"));
            if (partner != null) problems.Append(markB.Diff(partner, "mortal"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a mortal character was killed by the rift's own monsters " + deaths + " time(s) with no staff help: 0x28 once each, end 'left' with the lives, back at the entrance with the HUD, then 'failed' with the lost key, the next login at the temple, alive, no rift HUD, a step, no parse failure");
        }
    }
}
