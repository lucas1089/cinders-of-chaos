// The journey bot (O542, unity/README.md "Journey bots (O542)"): one character plays like a player, on the real protocol, for minutes or hours. No teleport, no staff command, no tester
// helper: it walks over the tiles it has seen (JourneyMap), picks a hunt by its level from the map marks of the installed server (data/chaos_poi.lua), fights with the Helper engine
// (Auto setup, the class rotation, heal rows) and its own back-up (heal spell, potions by thresholds), opens the bodies and takes the loot, walks to a shop when the bag or the
// capacity is full or the potions are low, sells and buys at the NPC, keeps gold, comes back after a death by the same road, and between hunts does what a player does (explores
// towns, talks to NPCs, opens the game's systems, stands still a while). Every decision rule is Core/Journey.cs (Core.Tests/JourneyTests.cs); this file is the play on a GameSession.
// A stuck event (no progress) is a finding, never repaired by a teleport: it is logged with the position and the bot walks away or gives the spot up.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;

namespace Chaos.Core.LiveCheck
{
    public sealed class JourneyOptions
    {
        /// <summary>Wall minutes the bot may play, the level it stops at, the file of the metrics JSON, data/chaos_poi.lua of the installed server, the random seed.</summary>
        public int Minutes = 180, TargetLevel = 25;
        public string OutFile, PoiFile;
        public ulong Seed = 1;
        /// <summary>The class name for the report (the character's class), free text.</summary>
        public string ClassName = "";
        /// <summary>Print a progress line every this many seconds.</summary>
        public int LogEverySec = 30;
    }

    sealed class JourneyInterrupt : Exception
    {
        public readonly string Why;
        public JourneyInterrupt(string why) : base(why) { Why = why; }
    }

    public sealed class JourneyRun
    {
        readonly LiveOptions lo;
        readonly JourneyOptions jo;
        readonly DatFile dat;
        readonly Dictionary<int, string> floorChanges;
        readonly HashSet<int> doorClient, ladderClient;
        readonly Dictionary<int, string> itemNames;
        readonly HashSet<Pos> useTiles = new HashSet<Pos>();
        readonly JourneyRng rng;
        public readonly JourneyMetrics M = new JourneyMetrics();
        readonly JourneyMap map = new JourneyMap();
        readonly List<MapMark> poi;
        readonly List<JourneyHunt> hunts;
        readonly Dictionary<string, long> avoidUntil = new Dictionary<string, long>();
        HashSet<string> avoid => new HashSet<string>(avoidUntil.Where(kv => kv.Value > Tick).Select(kv => kv.Key));
        void AvoidHunt(string key, double minutes) { avoidUntil[key] = Tick + (long)(minutes * 60000); }
        readonly HashSet<Pos> visitedFrontier = new HashSet<Pos>(), skipChanges = new HashSet<Pos>();
        readonly HashSet<string> visitedTowns = new HashSet<string>(), talkedNpcs = new HashSet<string>(), seenHunts = new HashSet<string>();
        readonly Dictionary<byte, int> opReplies = new Dictionary<byte, int>();
        readonly Dictionary<uint, double> ignoreMonster = new Dictionary<uint, double>();
        readonly List<OpPlan> opPlan = LiveOps.Plan();
        readonly StuckWatch watch = new StuckWatch();
        readonly StringBuilder log = new StringBuilder();

        LiveClient c;
        GameSession s;
        World world;
        GameParser p;
        HelperEngine engine;
        AutoWalkState auto = new AutoWalkState();
        Pos home, lastPos, lastGoodPos;
        JourneyHunt hunt;
        string lastThreat = "unknown";
        int lastHealth;
        int cancels0, expTexts0;
        long mapAt, obsAt, lastLog, bootMs, lastTripAt = -1, lastExploreAt, lastSystemAt, lastTalkAt, lastFightAt;
        double runStart;
        bool done;
        uint potionPrice; int healthPotionId, manaPotionId;
        string healthPotionName = "", manaPotionName = "";
        readonly HashSet<int> starterIds = new HashSet<int>();

        public JourneyRun(LiveOptions lo, JourneyOptions jo, DatFile dat, Dictionary<int, string> floorChanges, HashSet<int> doors, HashSet<int> ladders = null, Dictionary<int, string> names = null)
        {
            itemNames = names ?? new Dictionary<int, string>();
            ladderClient = ladders ?? new HashSet<int>();
            this.lo = lo; this.jo = jo; this.dat = dat; this.floorChanges = floorChanges ?? new Dictionary<int, string>(); doorClient = doors ?? new HashSet<int>();
            rng = new JourneyRng(jo.Seed);
            poi = jo.PoiFile != null && File.Exists(jo.PoiFile) ? JourneyHunts.ParsePoiLua(File.ReadAllText(jo.PoiFile)) : new List<MapMark>();
            hunts = JourneyHunts.FromMarks(poi);
        }

        static long Tick => Environment.TickCount64;
        double Min => (Tick - runStart) / 60000.0;

        void Say(string m)
        {
            string line = "[" + Min.ToString("0.0", CultureInfo.InvariantCulture) + " min L" + M.Level + "] " + m;
            log.AppendLine(line);
            Console.WriteLine(line);
            if (M.Notes.Count < 400) M.Notes.Add(line);
        }

        // ------------------------------------------------------------------------------------ connect
        bool Connect(out string err)
        {
            c = LiveClient.Connect(lo, dat, lo.Account, lo.Password, lo.Character, out err);
            if (c == null) return false;
            s = c.S; world = c.World; p = s.Parser;
            long end = Tick + 30000;
            while (Tick < end && !c.Entered && s.Closed == null) { c.Poll(); Thread.Sleep(10); }
            if (!c.Entered) { err = "no entry: " + (s.Closed ?? "timeout"); return false; }
            var prevExt = p.ExtendedOpcode;
            p.ExtendedOpcode = (op, data) => { opReplies[op] = opReplies.TryGetValue(op, out int n) ? n + 1 : 1; prevExt(op, data); };
            cancels0 = c.Cancels; expTexts0 = p.ExpGainTexts;
            auto = new AutoWalkState();
            engine = null;
            map.Cells.Clear(); map.Changes.Clear();   // tiles are seen again after a login
            lastHealth = p.Health;
            return true;
        }

        void Warm()
        {
            for (long end = Tick + 3500; Tick < end;) { c.Poll(); Thread.Sleep(10); }
            if (!s.Spells.Loaded) { s.Spells.Open(true); for (long end = Tick + 5000; Tick < end && !s.Spells.Loaded;) { c.Poll(); Thread.Sleep(10); } }
            engine = new HelperEngine(s.Spells, new SessionHelperHost(s));
            engine.Reach = s.AutoTargetReach;
            engine.RankOf = s.AutoTargetRank;
            int voc = s.Spells.Vocation != 0 ? s.Spells.Vocation : world.PlayerVocation;
            string m = engine.AutoSetup(voc);
            if (m != null) engine.AutoSupport();
            engine.Config.Enabled = true;
            engine.Config.MagicShooter = true;
            Say("Auto setup: " + (m ?? "no rotation") + ", " + engine.Config.Shooter.Count(x => x.Id > 0) + " slot(s), healing rows " + engine.Config.Heals.Count(h => h.Id != 0));
            s.SetFightModes(new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = true });
            OpenBag();
            if (starterIds.Count == 0) foreach (var cont in p.Containers.Values) foreach (var it in cont.Items) if (it != null) starterIds.Add(it.Id);
            home = c.Pos;
            if (home.X == 0) home = lastGoodPos;
            Pump(600);
        }

        void OpenBag()
        {
            if (p.Containers.Count > 0 || p.Inventory.Length <= 3 || p.Inventory[3] == null) return;
            s.UseItem(GameSession.InventoryPos(3), (ushort)p.Inventory[3].Id, 0);
            for (long end = Tick + 2500; Tick < end && p.Containers.Count == 0;) { c.Poll(); Thread.Sleep(10); }
        }

        // ------------------------------------------------------------------------------------ the heartbeat
        /// <summary>One slice of time: poll, the Helper engine, the map memory, the metrics, the back-up heal and potions. Throws JourneyInterrupt on a death or a lost connection.</summary>
        void Pump(int ms, Func<bool> until = null)
        {
            long end = Tick + ms;
            while (true)
            {
                Heartbeat();
                if (until != null && until()) return;
                if (Tick >= end) return;
                Thread.Sleep(8);
            }
        }

        void Heartbeat()
        {
            c.Poll();
            if (s.Closed != null) throw new JourneyInterrupt("closed: " + s.Closed);
            if (p.Dead) throw new JourneyInterrupt("dead");
            var me = world.Player;
            if (me == null) return;
            var pos = me.Position;
            if (pos.X > 0) { lastPos = pos; if (pos.X > 100) lastGoodPos = pos; }
            if (engine != null) { try { engine.Tick(); } catch (Exception e) when (!(e is JourneyInterrupt)) { if (M.Notes.Count < 400) M.Notes.Add("engine: " + e.GetType().Name + ": " + e.Message); } }
            auto.Update(pos, s.Now);
            long now = Tick;
            if (now - mapAt > 150) { mapAt = now; ScanMap(pos); }
            if (now - obsAt > 700)
            {
                obsAt = now;
                int h = p.Health;
                if (h < lastHealth) lastThreat = NearestMonsterName(pos, 4) ?? lastThreat;
                lastHealth = h;
                M.Observe(now - bootMs, p.Level, (long)p.Experience, Gold());
                if (p.ExpGainTexts > expTexts0) { for (int i = expTexts0; i < p.ExpGainTexts; i++) M.Kill(lastTargetName); expTexts0 = p.ExpGainTexts; }
                BackUp();
                if (p.Containers.Count == 0 && now - bagTryAt > 4000 && p.Inventory.Length > 3 && p.Inventory[3] != null) { bagTryAt = now; s.UseItem(GameSession.InventoryPos(3), (ushort)p.Inventory[3].Id, 0); }
                if (pos.X != progPos.X || pos.Y != progPos.Y || pos.Z != progPos.Z || (long)p.Experience != progExp) { progPos = pos; progExp = (long)p.Experience; progAt = now; }
                else if (now - progAt > 150000)
                {
                    // the whole-bot watchdog: nothing moved and no experience for 150 s, whatever the activity says it is doing
                    progAt = now;
                    throw new JourneyInterrupt("watchdog");
                }
                if (now - writeAt > 60000) { writeAt = now; WriteOut(false); }
                if (jo.LogEverySec > 0 && now - lastLog > jo.LogEverySec * 1000L)
                {
                    lastLog = now;
                    Say("pos " + pos + " hp " + p.Health + "/" + p.MaxHealth + " mana " + p.Mana + " exp " + p.Experience + " kills " + M.Kills + " gold " + M.GoldNow + " bags " + string.Join(",", p.Containers.Select(kv => kv.Key + ":" + kv.Value.Items.Count(i => i != null) + "/" + kv.Value.Capacity)) + " hunt " + (hunt?.Name ?? "-"));
                }
            }
            if (stopAsked && !done) { done = true; M.Stop = "stopped"; }
            if (p.Level >= jo.TargetLevel) done = true;
            if ((now - bootMs) / 60000.0 >= jo.Minutes) { done = true; M.Stop = "time"; }
        }

        string lastTargetName = "";
        long writeAt, bagTryAt, progAt;
        Pos progPos;
        long progExp = -1;
        volatile bool stopAsked;

        string NearestMonsterName(Pos pos, int within)
        {
            string best = null; int bd = int.MaxValue;
            foreach (var cr in world.Creatures.Values)
            {
                if (cr.Type != 1 || cr.Position.Z != pos.Z || cr.Position.X <= 0) continue;
                int d = PathFinder.Cheb(cr.Position, pos);
                if (d <= within && d < bd) { bd = d; best = JourneyHunts.BaseName(cr.Name); }
            }
            return best;
        }

        /// <summary>Gold carried: the coins in the open backpack (not in a body that is open). The last known value while the backpack is closed.</summary>
        long Gold()
        {
            if (p.Inventory.Length <= 3 || p.Inventory[3] == null) return M.GoldNow;
            long g = 0;
            bool open = false;
            foreach (var cont in p.Containers.Values)
            {
                if (cont.ItemId != p.Inventory[3].Id) continue;
                open = true;
                foreach (var it in cont.Items)
                {
                    if (it == null) continue;
                    int n = Math.Max(1, it.Count);
                    if (it.Id == 3031 || it.Id == 2148) g += n; else if (it.Id == 3035 || it.Id == 2152) g += 100L * n; else if (it.Id == 3043 || it.Id == 2160) g += 10000L * n;
                }
            }
            return open ? g : M.GoldNow;
        }

        JourneyVitals Vitals()
        {
            var v = new JourneyVitals { Health = p.Health, MaxHealth = p.MaxHealth, Mana = p.Mana, MaxMana = p.MaxMana, Level = p.Level, FreeCap = p.FreeCap, TotalCap = p.TotalCap, Gold = (ulong)Math.Max(0, M.GoldNow) };
            v.CanCast = p.MaxMana >= 60;
            CountPotions(out v.HealthPotions, out v.ManaPotions);
            var bag = p.Inventory.Length > 3 && p.Inventory[3] != null ? p.Containers.Values.FirstOrDefault(cc => cc.ItemId == p.Inventory[3].Id) : null;
            if (bag != null) v.BackpackFree = Math.Max(0, bag.Capacity - bag.Items.Count(i => i != null));
            return v;
        }

        long lastPotionAt, lastHealAt;

        string NameOf(int id) => itemNames.TryGetValue(id, out string n) ? n : "";

        /// <summary>Potions carried, by their names in items.xml ("Health Potion", "Strong Mana Potion"): counts, and the id to drink first (the carried one with the most of it).</summary>
        void CountPotions(out int health, out int mana)
        {
            health = mana = 0;
            int hBest = 0, mBest = 0, hId = 0, mId = 0;
            foreach (var cont in p.Containers.Values)
                foreach (var it in cont.Items)
                {
                    if (it == null) continue;
                    string n = NameOf(it.Id);
                    if (n.IndexOf("potion", StringComparison.OrdinalIgnoreCase) < 0) continue;
                    int cnt = Math.Max(1, it.Count);
                    if (n.IndexOf("health", StringComparison.OrdinalIgnoreCase) >= 0) { health += cnt; if (cnt > hBest) { hBest = cnt; hId = it.Id; } }
                    else if (n.IndexOf("mana", StringComparison.OrdinalIgnoreCase) >= 0) { mana += cnt; if (cnt > mBest) { mBest = cnt; mId = it.Id; } }
                }
            if (hId != 0) healthPotionId = hId;
            if (mId != 0) manaPotionId = mId;
        }

        /// <summary>The bot's own back-up of the Helper: the heal spell under 60 percent and potions under 40 (health) and 25 (mana) percent, a human's late reaction included.</summary>
        void BackUp()
        {
            var v = Vitals();
            long now = Tick;
            if (JourneyRules.DrinkHealth(v) && now - lastPotionAt > 1200 + rng.Next(900))
            {
                lastPotionAt = now;
                if (s.UseItemOnCreature((int)healthPotionId, world.PlayerId)) M.PotionsUsed++;
            }
            else if (JourneyRules.DrinkMana(v) && now - lastPotionAt > 1200 + rng.Next(900))
            {
                lastPotionAt = now;
                if (s.UseItemOnCreature((int)manaPotionId, world.PlayerId)) M.PotionsUsed++;
            }
            if (v.CanCast && v.HealthPct < JourneyRules.HealSpellPct && p.Mana >= 25 && now - lastHealAt > 1500) { lastHealAt = now; if (!engine.Config.Enabled) s.Say("exura"); }
        }

        // ------------------------------------------------------------------------------------ map memory
        void ScanMap(Pos pos)
        {
            if (pos.X <= 0) return;
            uint self = world.PlayerId;
            foreach (var tile in world.Tiles.Values)
            {
                var tp = tile.Pos;
                if (tp.Z != pos.Z) continue;
                int delta = 0;
                bool door = false;
                foreach (var th in tile.Things)
                {
                    if (th.IsCreature || th.Item == null) continue;
                    if (floorChanges.TryGetValue(th.Item.Id, out string fc)) delta = fc == "down" ? 1 : -1;
                    if (doorClient.Contains(th.Item.Id)) door = true;
                    if (ladderClient.Contains(th.Item.Id)) { delta = -1; useTiles.Add(tp); }
                }
                if (delta != 0) { map.Set(tp, JourneyMap.Cell.Change, delta); continue; }
                bool walk = WalkMap.Walkable(world, tp, self, true);
                if (!walk && door) { map.Set(tp, JourneyMap.Cell.Blocked); doors[tp] = true; continue; }
                map.Set(tp, walk ? JourneyMap.Cell.Walk : JourneyMap.Cell.Blocked);
                if (walk) doors.Remove(tp);
            }
            if (!areas.Contains(AreaKey(pos))) { areas.Add(AreaKey(pos)); NoteArea(pos); }
        }

        sealed class ChangeRec { public Pos From, Stair; public int ToZ, Kills; }
        readonly Stack<ChangeRec> changeLog = new Stack<ChangeRec>();
        readonly Dictionary<Pos, bool> doors = new Dictionary<Pos, bool>();
        readonly HashSet<string> areas = new HashSet<string>();
        static string AreaKey(Pos p) => (p.X / 64) + ":" + (p.Y / 64) + ":" + p.Z;

        void NoteArea(Pos pos)
        {
            M.Coverage.Touch("area", AreaKey(pos), Min);
            foreach (var m in poi)
            {
                if (m.Z != pos.Z || m.Kind != "temple") continue;
                if (PathFinder.Cheb(new Pos(m.X, m.Y, m.Z), pos) <= 45 && visitedTowns.Add(m.Name)) M.Coverage.Touch("town", m.Name, Min);
            }
            foreach (var h in hunts)
                if (h.At.Z == pos.Z && PathFinder.Cheb(h.At, pos) <= 14 && seenHunts.Add(h.Key)) M.Coverage.Touch("hunt", h.Name + " (" + h.Lo + "-" + h.Hi + ")", Min);
        }

        // ------------------------------------------------------------------------------------ walking
        /// <summary>Walks to `goal` (within `range`) over the tiles seen so far, exploring when the goal is not known yet, taking stairs and holes, opening doors. False with a reason on
        /// a give-up (no way, stuck, out of time). A fight that breaks out on the way is fought first. Never a teleport.</summary>
        bool Travel(Pos goal, int range, int budgetMs, out string why, string purpose)
        {
            why = "";
            long end = Tick + budgetMs;
            watch.Reset(s.Now);
            int replans = 0, noWay = 0, refusedSteps = 0;
            string lastNote = "";
            while (Tick < end && !done)
            {
                Pump(30);
                var pos = c.Pos;
                FightNearby();
                int st = watch.Observe(s.Now, pos, (long)p.Experience, true);
                if (st == 2)
                {
                    M.Stuck_(purpose + ": no progress toward " + goal, pos, hunt?.Name ?? "");
                    Say("stuck at " + pos + " going to " + goal + " (" + purpose + ")");
                    map.MarkBad(NextTile(pos, goal), Tick);
                    if (watch.GiveUps >= 2) { why = "stuck"; return false; }
                    WalkAway();
                    watch.Reset(s.Now);
                    continue;
                }
                if (st == 1) { replans++; auto.Cancel(); }
                var plan = JourneyNav.Next(map, pos, goal, Tick, range, visitedFrontier, skipChanges);
                switch (plan.What)
                {
                    case JourneyPlan.Kind.Arrived: return true;
                    case JourneyPlan.Kind.NoWay:
                        int reachN = map.Reach(pos, Tick, 2000).Count;
                        if (pos.Z == goal.Z && PathFinder.Cheb(pos, goal) <= 30 && purpose.StartsWith("to hunt", StringComparison.Ordinal))
                        {
                            // the mark may lie in a room the cave does not open to: close as the map allows is arrived, the monsters are in this area
                            Say("close to " + goal + " as the map allows (" + reachN + " tiles of this area known, no frontier): staying here");
                            return true;
                        }
                        bool smallPocket = reachN < 120 && changeLog.Count > 0 && changeLog.Peek().ToZ == pos.Z && changeLog.Peek().Kills == M.Kills;
                        if (!smallPocket && TryDoor(pos)) { noWay = 0; continue; }
                        if (changeLog.Count > 0 && changeLog.Peek().ToZ == pos.Z && changeLog.Peek().Kills == M.Kills && !purpose.StartsWith("patrol", StringComparison.Ordinal) && !purpose.StartsWith("back up", StringComparison.Ordinal) && map.Cells.Count(kv => kv.Key.Z == pos.Z) > 20)
                        {
                            if (RetreatFromDeadEnd("no way toward " + goal, pos, out string why2)) { noWay = 0; continue; }
                            why = "back up failed: " + why2; return false;
                        }
                        if (noWay == 0 && debugN++ < 6) { DumpMap(pos, 24, 12); var rch = map.Reach(pos, Tick); Say("no way debug: cells " + map.Cells.Count(kv => kv.Key.Z == pos.Z) + ", walk " + map.Cells.Count(kv => kv.Key.Z == pos.Z && kv.Value == JourneyMap.Cell.Walk) + ", reach " + rch.Count + ", frontier " + rch.Keys.Count(k => map.IsFrontier(k)) + ", bad " + map.Bad.Count + ", visitedFrontier " + visitedFrontier.Count + ", here " + map.Get(pos) + " at " + pos + ", goal cell " + map.Get(goal) + ", changes " + string.Join(" ", map.Changes.Where(kv => kv.Key.Z == pos.Z).Select(kv => kv.Key.X + "," + kv.Key.Y + (kv.Value > 0 ? "v" : "^"))) + ", doors " + doors.Count + " tried " + doorTried.Count + ", skip " + skipChanges.Count); Say("blockers next to the reachable tiles: " + string.Join(" ", map.Reach(pos, Tick, 400).Keys.SelectMany(rk => new[] { rk.Offset(1, 0), rk.Offset(-1, 0), rk.Offset(0, 1), rk.Offset(0, -1) }).Distinct().Where(q => map.Get(q) == JourneyMap.Cell.Blocked).Select(q => { var tt = world.Get(q); return q.X + "," + q.Y + "=" + (tt == null ? "?" : string.Join("/", tt.Things.Where(th => !th.IsCreature && th.Item != null).Select(th => th.Item.Id + (th.Item.Type != null && th.Item.Type.NotWalkable ? "N" : "") + (th.Item.Type != null && th.Item.Type.BlockPath ? "P" : "")))); }).Take(40))); Say("items near: " + string.Join(" ", world.Tiles.Values.Where(tl => tl.Pos.Z == pos.Z && PathFinder.Cheb(tl.Pos, pos) <= 3).SelectMany(tl => tl.Things.Where(th => !th.IsCreature && th.Item != null && th.Item.Type != null && !th.Item.Type.Ground).Select(th => th.Item.Id + "@" + tl.Pos.X + "," + tl.Pos.Y)).Take(40))); }
                        if (++noWay > 3) { why = "no way: " + plan.Note; M.Stuck_("no way toward " + goal + " (" + purpose + "): " + plan.Note, pos, hunt?.Name ?? ""); return false; }
                        visitedFrontier.Clear();
                        WalkAway();
                        continue;
                    case JourneyPlan.Kind.Step:
                        StepOnto(pos, plan.Target);
                        continue;
                    default:
                        if (plan.Note.Length > 0 && plan.Note != lastNote) { lastNote = plan.Note; }
                        if (!FollowPath(plan, pos, out bool refused)) { if (++refusedSteps > 6) { why = "steps refused"; M.Stuck_("steps refused toward " + goal, pos, hunt?.Name ?? ""); return false; } }
                        else refusedSteps = 0;
                        if (plan.What == JourneyPlan.Kind.Explore && PathFinder.Cheb(c.Pos, plan.Target) <= 1) visitedFrontier.Add(plan.Target);
                        break;
                }
            }
            why = done ? "done" : "time";
            return false;
        }


        /// <summary>The known map round a position as text (debug of a stuck place): . walk, # blocked, ^ v floor change, D door, @ the character, space unknown, c a creature.</summary>
        void DumpMap(Pos pos, int rx, int ry)
        {
            var sb = new StringBuilder();
            for (int y = pos.Y - ry; y <= pos.Y + ry; y++)
            {
                var row = new StringBuilder();
                for (int x = pos.X - rx; x <= pos.X + rx; x++)
                {
                    var q = new Pos(x, y, pos.Z);
                    var t = world.Get(q);
                    char ch = ' ';
                    switch (map.Get(q))
                    {
                        case JourneyMap.Cell.Walk: ch = '.'; break;
                        case JourneyMap.Cell.Blocked: ch = doors.ContainsKey(q) ? 'D' : '#'; break;
                        case JourneyMap.Cell.Change: ch = map.Changes.TryGetValue(q, out int dl) && dl > 0 ? 'v' : '^'; break;
                    }
                    if (t != null && t.Things.Any(th => th.IsCreature && th.Creature.Id != world.PlayerId)) ch = 'c';
                    if (x == pos.X && y == pos.Y) ch = '@';
                    row.Append(ch);
                }
                sb.AppendLine(row.ToString());
            }
            log.AppendLine("map round " + pos + " (x " + (pos.X - rx) + ".." + (pos.X + rx) + ", y " + (pos.Y - ry) + ".." + (pos.Y + ry) + "):\n" + sb);
        }

        /// <summary>A dead end below (a closed basement, a cellar with no monsters): the stair that led here is given up and the bot climbs back to the floor it came from.</summary>
        bool RetreatFromDeadEnd(string what, Pos pos, out string why)
        {
            why = "";
            var back = changeLog.Pop();
            skipChanges.Add(back.Stair);
            Say("dead end on floor " + pos.Z + " (" + what + "): back up, giving up the stair at " + back.Stair);
            M.Stuck_("dead end below the stair at " + back.Stair + " (" + what + ")", pos, hunt?.Name ?? "");
            visitedFrontier.Clear();
            return Travel(back.From, 1, 3 * 60000, out why, "back up");
        }

        bool CanRetreat(Pos pos) => changeLog.Count > 0 && changeLog.Peek().ToZ == pos.Z && changeLog.Peek().Kills == M.Kills;

        Pos NextTile(Pos pos, Pos goal)
        {
            int dx = Math.Sign(goal.X - pos.X), dy = Math.Sign(goal.Y - pos.Y);
            return new Pos(pos.X + dx, pos.Y + dy, pos.Z);
        }

        /// <summary>Sends the first stretch of a path as one auto-walk packet and waits until it ends.</summary>
        bool FollowPath(JourneyPlan plan, Pos from, out bool refused)
        {
            refused = false;
            bool monsterStop = false;
            var tiles = plan.Path;
            var dirs = new List<Dir>();
            for (int i = 1; i < tiles.Count && dirs.Count < 24; i++) dirs.Add(JourneyNav.DirOf(tiles[i - 1], tiles[i]));
            if (dirs.Count == 0) return true;
            int cancelsBefore = c.Cancels;
            WaitCanWalk();
            s.SendRaw(AutoWalkPackets.WalkPacket(dirs));
            auto.Start(from, dirs, s.Now);
            long limit = Tick + dirs.Count * 700 + 2500;
            int moves0 = p.PlayerMoves;
            while (auto.Active && Tick < limit && !done)
            {
                Pump(25);
                if (c.Cancels > cancelsBefore) { refused = true; break; }
                if (MonsterNear(2)) { monsterStop = true; auto.Cancel(); break; }
            }
            auto.Cancel();
            Pump(40 + rng.Next(120));
            bool moved = p.PlayerMoves > moves0;
            if (monsterStop) return true;
            if (refused || !moved)
            {
                // a creature in the way is no wall: only a tile that stays shut with nobody on it is avoided
                var next = tiles[Math.Min(1, tiles.Count - 1)];
                var nt = world.Get(next);
                bool occupied = nt != null && nt.Things.Any(th => th.IsCreature && th.Creature.Id != world.PlayerId);
                if (tiles.Count > 1 && !occupied && !MonsterNear(3)) map.MarkBad(next, Tick);
                return false;
            }
            return true;
        }

        void WaitCanWalk() { for (long end = Tick + 1500; Tick < end && !s.CanWalk;) Pump(15); }

        void StepOnto(Pos from, Pos target)
        {
            WaitCanWalk();
            var z0 = from.Z;
            if (useTiles.Contains(target))
            {
                // a ladder: used from the tile beside it
                var lt = world.Get(target);
                for (int i = lt == null ? -1 : lt.Things.Count - 1; i >= 0; i--)
                {
                    var th = lt.Things[i];
                    if (!th.IsCreature && th.Item != null && ladderClient.Contains(th.Item.Id)) { s.UseItem(target, (ushort)th.Item.Id, (byte)i); break; }
                }
            }
            else s.Walk(JourneyNav.DirOf(from, target));
            Pump(1100, () => c.Pos.Z != z0 || PathFinder.Cheb(c.Pos, from) > 0 && c.Pos.Z != z0);
            if (c.Pos.Z != z0) { changeLog.Push(new ChangeRec { From = from, Stair = target, ToZ = c.Pos.Z, Kills = M.Kills }); Say("floor change at " + target + ": " + z0 + " to " + c.Pos.Z); M.Coverage.Touch("map", "floor change " + z0 + "->" + c.Pos.Z, Min); visitedFrontier.Clear(); Pump(900); ScanMap(c.Pos); }
            else { skipChanges.Add(target); map.MarkBad(target, Tick); }
        }

        /// <summary>A walk of a few tiles in a random direction (the way out of a stuck spot or a dead end).</summary>
        void WalkAway()
        {
            var pos = c.Pos;
            var reach = map.Reach(pos, Tick, 600);
            var far = reach.Where(kv => kv.Value >= 4 && kv.Value <= 10).Select(kv => kv.Key).ToList();
            if (far.Count == 0) { Pump(500); return; }
            var t = far[rng.Next(far.Count)];
            var path = map.Path(pos, t, Tick);
            if (path == null || path.Count < 2) { Pump(300); return; }
            FollowPath(new JourneyPlan { What = JourneyPlan.Kind.Walk, Path = path, Target = t }, pos, out _);
        }

        /// <summary>A door in the known map beside a reachable tile: walk next to it and use it (what a player does at a shut door).</summary>
        bool TryDoor(Pos pos)
        {
            if (doors.Count == 0) return false;
            var reach = map.Reach(pos, Tick, 3000);
            Pos? best = null; int bd = int.MaxValue;
            foreach (var d in doors.Keys)
            {
                if (d.Z != pos.Z || doorTried.Contains(d)) continue;
                for (int i = 0; i < 4; i++)
                {
                    var n = new Pos(d.X + (i == 1 ? 1 : i == 3 ? -1 : 0), d.Y + (i == 0 ? -1 : i == 2 ? 1 : 0), d.Z);
                    if (reach.TryGetValue(n, out int dist) && dist < bd) { bd = dist; best = d; }
                }
            }
            if (!best.HasValue) return false;
            var door = best.Value;
            doorTried.Add(door);
            // stand beside it
            Pos? stand = null; int sd = int.MaxValue;
            for (int i = 0; i < 4; i++)
            {
                var n = new Pos(door.X + (i == 1 ? 1 : i == 3 ? -1 : 0), door.Y + (i == 0 ? -1 : i == 2 ? 1 : 0), door.Z);
                if (reach.TryGetValue(n, out int dist) && dist < sd) { sd = dist; stand = n; }
            }
            if (!stand.HasValue) return false;
            var path = map.Path(pos, stand.Value, Tick);
            if (path != null && path.Count > 1) FollowPath(new JourneyPlan { What = JourneyPlan.Kind.Walk, Path = path, Target = stand.Value }, pos, out _);
            var tile = world.Get(door);
            if (tile == null) return true;
            for (int i = tile.Things.Count - 1; i >= 0; i--)
            {
                var th = tile.Things[i];
                if (th.IsCreature || th.Item == null || !doorClient.Contains(th.Item.Id)) continue;
                s.UseItem(door, (ushort)th.Item.Id, (byte)i);
                Say("opened a door at " + door);
                M.Coverage.Touch("map", "door", Min);
                Pump(900);
                return true;
            }
            return true;
        }

        readonly HashSet<Pos> doorTried = new HashSet<Pos>();

        // ------------------------------------------------------------------------------------ fighting and loot
        bool MonsterNear(int within)
        {
            var pos = c.Pos;
            foreach (var cr in world.Creatures.Values)
                if (cr.Type == 1 && cr.Position.Z == pos.Z && cr.Position.X > 0 && PathFinder.Cheb(cr.Position, pos) <= within && !Ignored(cr.Id)) return true;
            return false;
        }

        bool Ignored(uint id) => ignoreMonster.TryGetValue(id, out double until) && until > Tick;

        void FightNearby()
        {
            if (!MonsterNear(3)) return;
            if (Tick - lastFightAt < 4000) return;
            lastFightAt = Tick;
            Fight(10000, null);
        }

        Creature PickTarget(JourneyHunt h, int within)
        {
            var pos = c.Pos;
            Creature best = null; int bd = int.MaxValue;
            foreach (var cr in world.Creatures.Values)
            {
                if (cr.Type != 1 || cr.Position.Z != pos.Z || cr.Position.X <= 0 || Ignored(cr.Id)) continue;
                int d = PathFinder.Cheb(cr.Position, pos);
                if (d > within) continue;
                if (h != null && !JourneyHunts.Wants(h, cr.Name) && d > 2) continue;
                if (d < bd) { bd = d; best = cr; }
            }
            return best;
        }

        /// <summary>Kills what is near: attack the nearest wanted monster, keep attacking while it lives, then open its body and take the loot. Returns the kills.</summary>
        int Fight(int budgetMs, JourneyHunt h)
        {
            int kills = 0;
            long end = Tick + budgetMs;
            watch.Reset(s.Now);
            while (Tick < end && !done)
            {
                var t = PickTarget(h, 8);
                if (t == null) break;
                lastTargetName = t.Name;
                Pump((int)JourneyActivities.ReactionMs(rng));
                s.Attack(t.Id);
                long fightStart = Tick, lastAtk = Tick;
                Pos lastSeen = t.Position;
                bool dead = false;
                while (Tick < end && !done)
                {
                    Pump(60);
                    var cr = world.Creatures.TryGetValue(t.Id, out var x) ? x : null;
                    if (cr == null || cr.Position.X <= 0 || cr.Position.Z != c.Pos.Z) { dead = true; break; }
                    lastSeen = cr.Position;
                    if (Tick - lastAtk > 2500 && p.AttackTarget != t.Id) { s.Attack(t.Id); lastAtk = Tick; }
                    int st = watch.Observe(s.Now, c.Pos, (long)p.Experience + cr.HealthPercent, true);
                    if (st == 2 || Tick - fightStart > 35000)
                    {
                        M.Stuck_("fight: no progress against " + t.Name, c.Pos, h?.Name ?? "");
                        ignoreMonster[t.Id] = Tick + 90000;
                        s.CancelAttack();
                        break;
                    }
                    if (PathFinder.Cheb(cr.Position, c.Pos) > 1 && !s.CanWalk && Tick - fightStart > 12000) break;
                }
                if (dead)
                {
                    kills++;
                    Pump(500 + rng.Next(500));
                    Loot(lastSeen);
                }
            }
            return kills;
        }

        /// <summary>Opens the body on or beside the kill tile and moves what is in it to the backpack, a human way (gold and the useful first, junk too: the town trip sells it).</summary>
        void Loot(Pos at)
        {
            var found = LiveFirstFightStep.LootOn(world, at);
            if (found == null) return;
            var pos = c.Pos;
            if (PathFinder.Cheb(found.Tile, pos) > 1)
            {
                var path = map.Path(pos, found.Tile, Tick, 3000, 1);
                if (path != null && path.Count > 1) FollowPath(new JourneyPlan { What = JourneyPlan.Kind.Walk, Path = path, Target = path[path.Count - 1] }, pos, out _);
            }
            var before = new HashSet<byte>(p.Containers.Keys);
            s.UseItem(found.Tile, (ushort)found.ItemId, (byte)found.Stack);
            Pump(1800, () => p.Containers.Keys.Any(k => !before.Contains(k)));
            var body = p.Containers.Where(kv => !before.Contains(kv.Key)).Select(kv => kv.Value).FirstOrDefault();
            if (body == null) return;
            int taken = 0;
            var bag = p.Containers.Where(kv => before.Contains(kv.Key)).Select(kv => kv.Value).FirstOrDefault();
            for (int i = body.Items.Count - 1; i >= 0; i--)
            {
                var it = body.Items[i];
                if (it == null) continue;
                if (bag != null && bag.Items.Count(x => x != null) >= bag.Capacity && !IsCoin(it.Id)) break;
                byte cnt = (byte)Math.Max(1, Math.Min(100, it.Count));
                s.SendRaw(Protocol.MoveItemPacket(GameSession.ContainerPos(body.Id, body.FirstIndex + i), (ushort)it.Id, (byte)(body.FirstIndex + i), GameSession.InventoryPos(3), cnt));
                taken++;
                Pump(140 + rng.Next(160));
            }
            if (taken > 0) M.Coverage.Touch("system", "loot", Min);
            s.CloseContainer(body.Id);
            Pump(200);
        }

        static bool IsCoin(int id) => id == 3031 || id == 3035 || id == 3043 || id == 2148 || id == 2152 || id == 2160;

        // ------------------------------------------------------------------------------------ hunting
        void DoHunt(double sliceMs)
        {
            if (hunt == null || p.Level > hunt.Hi + 2 || (avoidUntil.TryGetValue(hunt.Key, out long avUntil) && avUntil > Tick))
            {
                hunt = JourneyHunts.Pick(hunts, p.Level, lastGoodPos, avoid, rng);
                if (hunt == null) { hunt = JourneyHunts.Pick(hunts, p.Level, lastGoodPos, avoid, rng, 900); if (hunt != null) Say("a far hunt for level " + p.Level); }
                if (hunt == null && avoidUntil.Count > 0)
                {
                    // every hunt in reach was given up: forget that (the map is better known now, the way may open) and try once more
                    Say("every hunt in reach was given up: trying them again");
                    avoidUntil.Clear(); visitedFrontier.Clear(); skipChanges.Clear(); doorTried.Clear();
                    hunt = JourneyHunts.Pick(hunts, p.Level, lastGoodPos, avoid, rng, 900);
                    if (hunt != null) M.Hunts.Add(hunt.Name + " (" + hunt.Lo + "-" + hunt.Hi + ") at " + hunt.At + " again from minute " + Min.ToString("0.0", CultureInfo.InvariantCulture));
                }
                if (hunt == null) { Say("no hunt for level " + p.Level + ": exploring instead"); DoExplore(); Pump(3000); return; }
                M.Hunts.Add(hunt.Name + " (" + hunt.Lo + "-" + hunt.Hi + ") at " + hunt.At + " from minute " + Min.ToString("0.0", CultureInfo.InvariantCulture));
                Say("hunt: " + hunt.Name + " (level " + hunt.Lo + "-" + hunt.Hi + ") at " + hunt.At);
            }
            if (PathFinder.Cheb(c.Pos, hunt.At) > 24 || c.Pos.Z != hunt.At.Z)
            {
                if (!Travel(hunt.At, 4, (int)(Math.Min(20, 6 + PathFinder.Cheb(c.Pos, hunt.At) / 40.0) * 60000), out string why, "to hunt " + hunt.Name))
                {
                    if (done) return;
                    Say("gave up the way to " + hunt.Name + ": " + why);
                    AvoidHunt(hunt.Key, why == "time" ? 4 : 30); M.GaveUpHunts++; hunt = null;
                    return;
                }
                Say("arrived at the hunt " + hunt.Name);
            }
            long end = Tick + (long)sliceMs;
            long lastKillAt = Tick;
            int quiet = 0;
            bool centre = false;
            while (Tick < end && !done)
            {
                Pump(100);
                var reason = JourneyRules.TownTrip(Vitals(), lastTripAt < 0 ? 1e12 : Tick - lastTripAt, potionPrice);
                if (reason.Length > 0) return;
                if (p.Level > hunt.Hi + 2) return;
                int k = Fight(15000, hunt);
                if (k > 0) { lastKillAt = Tick; quiet = 0; continue; }
                if (Tick - lastKillAt > 45000 && CanRetreat(c.Pos) && PathFinder.Cheb(c.Pos, hunt.At) <= 40 && map.Reach(c.Pos, Tick, 1500).Count < 350)
                {
                    // no monster here and a small area below the stair: a cellar, not the cave. Climb out and take another stair.
                    if (RetreatFromDeadEnd("no monsters in this small area", c.Pos, out string whyR)) return;
                    Say("could not climb out: " + whyR);
                }
                if (!centre && PathFinder.Cheb(c.Pos, hunt.At) > 4 && Tick - lastKillAt > 15000)
                {
                    // near the mark is not at the mark: a cellar next to the cave counts as near. Walk to the centre itself (the way there may need another stair)
                    centre = true;
                    if (!Travel(hunt.At, 3, 2 * 60000, out string whyC, "to the centre of " + hunt.Name)) { if (done) return; Say("no way to the centre of " + hunt.Name + ": " + whyC + " (the monsters may live elsewhere in this cave)"); }
                    continue;
                }
                if (Tick - lastKillAt > 150000)
                {
                    Say("no monster for 150 s at " + hunt.Name + ": giving the spot up");
                    M.Stuck_("no monsters for 150 s", c.Pos, hunt.Name);
                    AvoidHunt(hunt.Key, 20); M.GaveUpHunts++; hunt = null;
                    return;
                }
                // patrol the hunt: a known tile around its centre, a short walk, a pause
                var around = map.Cells.Where(kv => kv.Value == JourneyMap.Cell.Walk && kv.Key.Z == hunt.At.Z && PathFinder.Cheb(kv.Key, hunt.At) <= 14 && PathFinder.Cheb(kv.Key, c.Pos) >= 4).Select(kv => kv.Key).ToList();
                if (around.Count > 0 && ++quiet % 2 == 0)
                {
                    var t = around[rng.Next(around.Count)];
                    Travel(t, 1, 30000, out _, "patrol");
                }
                else Pump((int)JourneyActivities.IdleMs(rng) / 4);
            }
        }

        // ------------------------------------------------------------------------------------ town
        MapMark NearestMark(string kind, Pos from, Func<MapMark, bool> pred = null, ISet<string> skip = null)
        {
            MapMark best = null; int bd = int.MaxValue;
            foreach (var m in poi)
            {
                if (m.Kind != kind || (pred != null && !pred(m)) || (skip != null && skip.Contains(m.Key))) continue;
                int d = PathFinder.Cheb(new Pos(m.X, m.Y, m.Z), from) + 30 * Math.Abs(m.Z - from.Z);
                if (d < bd && d < 300) { bd = d; best = m; }
            }
            return best;
        }

        static bool Junk(string name)
        {
            string n = (name ?? "").ToLowerInvariant();
            return !(n.Contains("potion") || n.Contains("rune") || n.Contains("arrow") || n.Contains("bolt") || n.Contains("spear") || n.Contains("backpack") || n.Contains("bag"));
        }

        void DoTown(string reason)
        {
            double t0 = Min;
            long gold0 = M.GoldNow;
            Say("town trip: " + reason);
            var skip = new HashSet<string>(noPotionShops);
            long sold = 0; bool done1 = false;
            for (int attempt = 0; attempt < 3 && !done1 && !done; attempt++)
            {
                var shop = NearestMark("shop", c.Pos, null, skip);
                if (shop == null) { Say("no shop mark known near " + c.Pos); break; }
                skip.Add(shop.Key);
                var spos = new Pos(shop.X, shop.Y, shop.Z);
                if (!Travel(spos, 2, 6 * 60000, out string why, "to shop " + shop.Name)) { Say("could not reach " + shop.Name + ": " + why); continue; }
                string npc = shop.Name.Replace(" (shop)", "");
                var cr = world.Creatures.Values.FirstOrDefault(x => x.Type == 2 && string.Equals(JourneyHunts.BaseName(x.Name), npc, StringComparison.OrdinalIgnoreCase));
                if (cr != null && PathFinder.Cheb(cr.Position, c.Pos) > 2) Travel(cr.Position, 2, 40000, out _, "to npc");
                Pump(400 + rng.Next(500));
                if (!OpenTrade(npc)) { Say("no trade window at " + npc); M.Coverage.Fail("npc", npc + " trade", Min, "no trade window"); continue; }
                M.Coverage.Touch("npc", npc + " trade", Min);
                sold += SellLoot();
                bool potions = BuyPotions();
                s.NpcClose();
                done1 = potions;
                if (!potions) { noPotionShops.Add(shop.Key); Say(npc + " sells no potions: trying the next shop"); }
            }
            if (reason == "potions" || reason == "cap" || reason == "backpack") lastTripAt = Tick;
            lastTripAt = Tick;
            M.Trips.Add(new JourneyMetrics.Trip { Reason = reason, AtMin = t0, LevelAt = p.Level, Minutes = Min - t0, Sold = sold });
            Pump(300);
        }

        bool OpenTrade(string npc)
        {
            int lines0 = p.NpcTalk.Lines.Count;
            s.SayToNpc("hi");
            if (!WaitUntil(6000, () => p.NpcTalk.Lines.Skip(lines0).Any(l => l.FromNpc))) return false;
            Pump(300 + rng.Next(400));
            int shops0 = p.Seen.TryGetValue(0x7A, out int n0) ? n0 : 0;
            s.SayToNpc("trade");
            return WaitUntil(6000, () => p.Trade.Open && p.Trade.Items.Count > 0 && p.Seen.TryGetValue(0x7A, out int n) && n > shops0);
        }

        bool WaitUntil(int ms, Func<bool> f) { bool ok = false; Pump(ms, () => ok = f()); return ok; }

        long SellLoot()
        {
            long total = 0;
            Pump(500);
            var list = p.Trade.SellList(null).Where(i => Junk(i.Name) && !starterIds.Contains(i.Id)).ToList();
            foreach (var row in list)
            {
                int have = p.Trade.GoodsCount(row.Id);
                while (have > 0 && !done)
                {
                    int amt = Math.Min(have, NpcTradeState.MaxAmount);
                    ulong m0 = p.Trade.Money;
                    if (!s.NpcSell(row, amt, true)) break;
                    Pump(700 + rng.Next(400), () => p.Trade.Money != m0);
                    int now = p.Trade.GoodsCount(row.Id);
                    if (now >= have) break;
                    total += (long)row.Sell * (have - now);
                    have = now;
                }
            }
            Say("sold loot for " + total + " gold (" + list.Count + " kinds)");
            if (total > 0) M.Coverage.Touch("system", "sell loot", Min);
            return total;
        }

        bool BuyPotions()
        {
            var hp = p.Trade.Items.Where(i => i.Buyable && i.Name.IndexOf("health potion", StringComparison.OrdinalIgnoreCase) >= 0).OrderBy(i => i.Buy).FirstOrDefault();
            var mp = p.Trade.Items.Where(i => i.Buyable && i.Name.IndexOf("mana potion", StringComparison.OrdinalIgnoreCase) >= 0).OrderBy(i => i.Buy).FirstOrDefault();
            if (hp != null) { healthPotionId = hp.Id; healthPotionName = hp.Name; potionPrice = hp.Buy; }
            if (mp != null) { manaPotionId = mp.Id; manaPotionName = mp.Name; if (potionPrice == 0) potionPrice = mp.Buy; }
            ulong money = p.Trade.Money;
            foreach (var it in new[] { hp, mp })
            {
                if (it == null) continue;
                if (it == mp && p.MaxMana < 60) continue;
                int have = s.CountItem(it.Id);
                int n = JourneyRules.BuyCount(money, have, it.Buy);
                if (n <= 0) continue;
                if (!s.NpcBuy(it, Math.Min(n, NpcTradeState.MaxAmount), false) && !s.NpcBuy(it, Math.Min(n, NpcTradeState.MaxAmount), true)) continue;
                Pump(900);
                M.PotionsBought += n;
                money = p.Trade.Money;
                Say("bought " + n + " x " + it.Name);
                M.Coverage.Touch("system", "buy potions", Min);
            }
            return hp != null || mp != null;
        }

        // ------------------------------------------------------------------------------------ the other things a player does
        void DoExplore()
        {
            lastExploreAt = Tick;
            var from = lastGoodPos;
            var town = poi.Where(m => m.Kind == "temple" && !visitedTowns.Contains(m.Name) && !exploreFailed.Contains(m.Name) && PathFinder.Cheb(new Pos(m.X, m.Y, m.Z), from) <= 700)
                .OrderBy(m => PathFinder.Cheb(new Pos(m.X, m.Y, m.Z), from) + 30 * Math.Abs(m.Z - from.Z)).FirstOrDefault();
            if (town != null)
            {
                Say("exploring toward " + town.Name + " at " + town.X + "," + town.Y + "," + town.Z);
                var g = new Pos(town.X, town.Y, town.Z);
                if (Travel(g, 5, 7 * 60000, out string why, "explore " + town.Name)) { Say("reached " + town.Name); M.Coverage.Touch("town", town.Name, Min, "walked"); visitedTowns.Add(town.Name); Pump((int)JourneyActivities.IdleMs(rng)); }
                else if (!done) { exploreFailed.Add(town.Name); M.Coverage.Fail("town", town.Name, Min, why); Say("could not reach " + town.Name + ": " + why); }
                return;
            }
            // no town left: walk to an unvisited frontier near home
            var fr = map.ExploreToward(c.Pos, home, Tick, visitedFrontier);
            if (fr.HasValue) Travel(fr.Value, 1, 60000, out _, "explore frontier");
            else Pump(2000);
        }

        readonly HashSet<string> exploreFailed = new HashSet<string>();

        void DoTalk()
        {
            lastTalkAt = Tick;
            var npc = world.Creatures.Values.Where(x => x.Type == 2 && x.Position.Z == c.Pos.Z && x.Position.X > 0 && !talkedNpcs.Contains(JourneyHunts.BaseName(x.Name)))
                .OrderBy(x => PathFinder.Cheb(x.Position, c.Pos)).FirstOrDefault();
            if (npc == null)
            {
                var m = NearestMark("shop", c.Pos, x => !talkedNpcs.Contains(x.Name.Replace(" (shop)", "")));
                if (m == null) return;
                Travel(new Pos(m.X, m.Y, m.Z), 3, 4 * 60000, out _, "to talk");
                npc = world.Creatures.Values.FirstOrDefault(x => x.Type == 2 && x.Position.Z == c.Pos.Z);
                if (npc == null) return;
            }
            string name = JourneyHunts.BaseName(npc.Name);
            talkedNpcs.Add(name);
            if (PathFinder.Cheb(npc.Position, c.Pos) > 2 && !Travel(npc.Position, 2, 60000, out string why, "to npc " + name)) { M.Coverage.Fail("npc", name, Min, why); return; }
            int lines0 = p.NpcTalk.Lines.Count;
            s.SayToNpc("hi");
            bool answered = WaitUntil(5000, () => p.NpcTalk.Lines.Skip(lines0).Any(l => l.FromNpc));
            if (!answered) { M.Coverage.Fail("npc", name, Min, "no answer to hi"); return; }
            M.Coverage.Touch("npc", name, Min);
            foreach (var w in new[] { "job", "quest", "tales", "help" })
            {
                Pump(1200 + rng.Next(1800));
                int n0 = p.NpcTalk.Lines.Count;
                s.SayToNpc(w);
                if (WaitUntil(3000, () => p.NpcTalk.Lines.Skip(n0).Any(l => l.FromNpc))) { M.Coverage.Touch("npc", name + " '" + w + "'", Min); if (w == "quest" || w == "tales") M.Coverage.Touch("system", "quest talk", Min, name); }
            }
            s.SayToNpc("bye");
            Pump(600);
        }

        int systemIndex, debugN;
        readonly HashSet<string> noPotionShops = new HashSet<string>();

        /// <summary>Opens one game system the way its window does (the first request of the module, LiveOps), and records the answer: touched, or failed with the error.</summary>
        void DoSystem()
        {
            lastSystemAt = Tick;
            foreach (var pl in opPlan) M.Coverage.Declare("opcode", pl.Op + " " + pl.Name);
            // a player who opens the menus opens several windows in a row, with a pause to read each
            int windows = rng.Range(3, 7);
            for (int w = 0; w < windows && !done; w++)
            {
                var todo = opPlan.Where(pl => pl.Kind == "request" && M.Coverage.Get("opcode", pl.Op + " " + pl.Name).What == JourneyCoverage.State.NotTouched).ToList();
                if (todo.Count == 0) return;
                var pick = todo[rng.Next(Math.Min(todo.Count, 6))];
                string key = pick.Op + " " + pick.Name;
                int replies0 = opReplies.TryGetValue(pick.Op, out int n) ? n : 0;
                int errors0 = c.ExtErrors;
                if (pick.Text) s.Ext.SendText(pick.Op, pick.Action); else s.Ext.Send(pick.Op, pick.Action, pick.Data);
                bool got = WaitUntil(2500, () => (opReplies.TryGetValue(pick.Op, out int m) ? m : 0) > replies0);
                string silent;
                if (c.ExtErrors > errors0) { M.Coverage.Fail("opcode", key, Min, "the client handler threw or the JSON was invalid"); M.Coverage.Fail("system", pick.Name, Min, "client error"); }
                else if (got) { M.Coverage.Touch("opcode", key, Min, pick.Action); M.Coverage.Touch("system", pick.Name, Min); }
                else if (LiveOps.Silent.TryGetValue(pick.Op, out silent)) { M.Coverage.Touch("opcode", key, Min, "silent: " + silent); M.Coverage.Touch("system", pick.Name, Min, "silent: " + silent); }
                else { M.Coverage.Fail("opcode", key, Min, "no reply to " + pick.Action); M.Coverage.Fail("system", pick.Name, Min, "no reply to " + pick.Action); }
                Pump(1500 + rng.Next(3500));
                systemIndex++;
            }
        }

        void DoBank()
        {
            if (M.GoldNow < 400) return;
            var bank = NearestMark("bank", c.Pos);
            if (bank == null) return;
            if (!Travel(new Pos(bank.X, bank.Y, bank.Z), 2, 5 * 60000, out string why, "to bank")) { M.Coverage.Fail("system", "bank deposit", Min, why); return; }
            string npc = bank.Name.Replace(" (bank)", "");
            int lines0 = p.NpcTalk.Lines.Count;
            s.SayToNpc("hi");
            if (!WaitUntil(5000, () => p.NpcTalk.Lines.Skip(lines0).Any(l => l.FromNpc))) { M.Coverage.Fail("system", "bank deposit", Min, "banker " + npc + " did not answer"); return; }
            Pump(500);
            long g0 = Gold();
            s.SayToNpc("deposit all"); Pump(1200);
            s.SayToNpc("yes"); Pump(1500);
            M.Coverage.Touch("system", "bank deposit", Min, npc + (Gold() < g0 ? ": deposited " + (g0 - Gold()) : ": nothing taken"));
            s.SayToNpc("bye");
        }

        // ------------------------------------------------------------------------------------ death and reconnect
        void Recover(string why)
        {
            var at = lastGoodPos;
            if (why == "watchdog")
            {
                var near = world.Creatures.Values.Where(x => x.Position.Z == at.Z && x.Position.X > 0 && PathFinder.Cheb(x.Position, at) <= 6).Select(x => (x.Type == 1 ? "monster " : x.Type == 2 ? "npc " : "creature ") + x.Name + " " + x.HealthPercent + "% at " + x.Position).Take(8).ToList();
                M.Stuck_("whole-bot watchdog: no step and no experience for 150 s (activity " + activity + "); near: " + string.Join("; ", near), at, hunt?.Name ?? "");
                Say("watchdog: nothing moved for 150 s at " + at + " (" + activity + "); near: " + string.Join("; ", near));
                foreach (var cr in world.Creatures.Values) if (cr.Type == 1) ignoreMonster[cr.Id] = Tick + 180000;
                s.CancelAttack(); auto.Cancel();
                try { DumpMap(at, 24, 12); WalkAway(); } catch (JourneyInterrupt) { }
                if (hunt != null) { AvoidHunt(hunt.Key, 10); hunt = null; }
                visitedFrontier.Clear();
                return;
            }
            bool dead = why.StartsWith("dead", StringComparison.Ordinal);
            if (dead) { M.Died(lastThreat, at); Say("died at " + at + " to " + lastThreat + " (level " + p.Level + ")"); if (hunt != null && M.Deaths.Count(d => PathFinder.Cheb(d.At, hunt.At) < 40) >= 2) { AvoidHunt(hunt.Key, 60); hunt = null; Say("two deaths at that hunt: giving it up"); } }
            else { Say("connection lost: " + why); }
            try { c.Close(); } catch (Exception) { }
            for (int attempt = 1; attempt <= 12 && !done; attempt++)
            {
                Thread.Sleep(dead ? 4000 + rng.Next(6000) : 3000);
                if (Connect(out string err)) { M.Reconnects++; Warm(); Say("back in the game at " + c.Pos); return; }
                Say("login failed (" + attempt + "): " + err);
                Thread.Sleep(5000 * attempt);
            }
            done = true; M.Stop = "no login";
        }

        // ------------------------------------------------------------------------------------ the loop
        public int Execute()
        {
            using (System.Runtime.InteropServices.PosixSignalRegistration.Create(System.Runtime.InteropServices.PosixSignal.SIGTERM, ctx => { ctx.Cancel = true; stopAsked = true; }))
            using (System.Runtime.InteropServices.PosixSignalRegistration.Create(System.Runtime.InteropServices.PosixSignal.SIGINT, ctx => { ctx.Cancel = true; stopAsked = true; }))
                return Run();
        }

        int Run()
        {
            if (!Connect(out string err)) { Console.Error.WriteLine("journey: " + err); return 1; }
            bootMs = Tick; runStart = Tick;
            M.Name = c.Character; M.Class = jo.ClassName; M.Vocation = world.PlayerVocation;
            Warm();
            M.Observe(0, p.Level, (long)p.Experience, Gold());
            M.Begin(0, p.Level, (long)p.Experience, Gold());
            foreach (var h in hunts) M.Coverage.Declare("hunt", h.Name + " (" + h.Lo + "-" + h.Hi + ")");
            foreach (var m in poi) if (m.Kind == "temple") M.Coverage.Declare("town", m.Name);
            foreach (var pl in opPlan) M.Coverage.Declare("opcode", pl.Op + " " + pl.Name);
            foreach (string sname in new[] { "loot", "sell loot", "buy potions", "bank deposit", "quest talk" }) M.Coverage.Declare("system", sname);
            Say("journey starts: " + c.Character + " level " + p.Level + " at " + c.Pos + ", " + hunts.Count + " hunts and " + poi.Count + " marks known, goal level " + jo.TargetLevel + " or " + jo.Minutes + " min");
            lastExploreAt = lastSystemAt = lastTalkAt = Tick;
            while (!done)
            {
                try
                {
                    Pump(50);
                    OpenBag();
                    var reason = JourneyRules.TownTrip(Vitals(), lastTripAt < 0 ? 1e12 : Tick - lastTripAt, potionPrice);
                    var ctx = new JourneyActivities.Context
                    {
                        Level = p.Level, TripReason = reason,
                        MinutesSinceExplore = (Tick - lastExploreAt) / 60000.0, MinutesSinceSystem = (Tick - lastSystemAt) / 60000.0, MinutesSinceTalk = (Tick - lastTalkAt) / 60000.0,
                        UnvisitedTowns = poi.Count(m => m.Kind == "temple" && !visitedTowns.Contains(m.Name) && !exploreFailed.Contains(m.Name)),
                        UntouchedSystems = opPlan.Count(pl => pl.Kind == "request" && M.Coverage.Get("opcode", pl.Op + " " + pl.Name)?.What == JourneyCoverage.State.NotTouched),
                        UntalkedNpcs = 3 - Math.Min(3, talkedNpcs.Count) + 1,
                    };
                    var act = firstHunts-- > 0 && reason.Length == 0 ? JourneyActivity.Hunt : JourneyActivities.Choose(ctx, rng);
                    activity = act.ToString();
                    switch (act)
                    {
                        case JourneyActivity.Hunt: DoHunt(JourneyActivities.HuntSliceMs(rng)); break;
                        case JourneyActivity.Town: DoTown(reason); if (M.GoldNow > 2000 && rng.Next(3) == 0) DoBank(); break;
                        case JourneyActivity.Explore: if (p.Level >= 3) DoExplore(); break;
                        case JourneyActivity.Talk: DoTalk(); break;
                        case JourneyActivity.System: DoSystem(); break;
                        default: Pump((int)JourneyActivities.IdleMs(rng)); break;
                    }
                }
                catch (JourneyInterrupt e) { if (!done) Recover(e.Why); }
            }
            Finish();
            return 0;
        }

        int firstHunts = 2;
        string activity = "start";

        void Finish()
        {
            M.Observe(Tick - bootMs, p.Level, (long)p.Experience, Gold());
            if (M.Stop.Length == 0) M.Stop = p.Level >= jo.TargetLevel ? "level " + p.Level : "stopped";
            Say("journey ends: level " + p.Level + " after " + M.Minutes.ToString("0.0", CultureInfo.InvariantCulture) + " min, " + M.Kills + " kills, " + M.Deaths.Count + " deaths, " + M.Stuck.Count + " stuck events, stop: " + M.Stop);
            try { c.Close(); } catch (Exception) { }
            WriteOut(true);
        }

        /// <summary>The numbers of the bot as JSON (and the log and coverage table as text beside it), at the end and every minute, so a status or a report can read a running bot.</summary>
        void WriteOut(bool final)
        {
            if (jo.OutFile == null) return;
            try
            {
                string tmp = jo.OutFile + ".tmp";
                File.WriteAllText(tmp, Json.Serialize(M.ToJson()) + "\n");
                File.Move(tmp, jo.OutFile, true);
                File.WriteAllText(Path.ChangeExtension(jo.OutFile, ".txt"), log + "\n" + M.Coverage.Table());
                if (final) Console.WriteLine("journey report: " + jo.OutFile);
            }
            catch (IOException) { }
        }
    }
}
