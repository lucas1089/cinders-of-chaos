// Phase 6, track V: the pure parts of the P0 user experience: the pathfinder and the auto-walk packets, the eased plate bars, the split stack model, the NPC
// bubble layout and walk-up, the login news and account API parsing, the bag panel and the party frames settings.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class Phase6VTests
    {
        static string Hex(byte[] b) => string.Concat(b.Select(x => x.ToString("x2")));

        public static void Run(Action<bool, string> check)
        {
            Paths(check);
            Packets(check);
            WalkState(check);
            WalkMapChecks(check);
            Bars(check);
            Split(check);
            Bubble(check);
            Login(check);
            Account(check);
            Panels(check);
            Texts(check);
        }

        static Func<Pos, bool> Open(params string[] blocked)
        {
            var set = new HashSet<string>(blocked);
            return p => !set.Contains(p.X + "," + p.Y) && p.X >= 0 && p.X < 12 && p.Y >= 0 && p.Y < 12;
        }

        static void Paths(Action<bool, string> check)
        {
            var from = new Pos(1, 1, 7);
            var straight = PathFinder.Find(from, new Pos(4, 1, 7), Open());
            check(straight != null && straight.Count == 3 && straight.All(d => d == Dir.East), "path: a straight line goes east three times");
            var diag = PathFinder.Find(from, new Pos(3, 3, 7), Open());
            check(diag != null && diag.Count == 4 && diag.All(d => !WalkDirs.Diagonal(d)), "path: straight steps are preferred to diagonals (a diagonal costs three)");
            // a wall with a gap: the path goes round and ends on the goal
            var walls = new List<string>();
            for (int y = 0; y < 11; y++) walls.Add("3," + y);   // x = 3 is blocked except y = 11
            var round = PathFinder.Find(from, new Pos(5, 1, 7), Open(walls.ToArray()));
            check(round != null && PathFinder.Tiles(from, round).Last() == new Pos(5, 1, 7) && round.Count >= 20, "path: round a wall through the gap");
            check(PathFinder.Find(from, new Pos(5, 1, 7), Open(walls.Concat(new[] { "3,11" }).ToArray())) == null, "path: no gap, no way");
            check(PathFinder.Find(from, new Pos(5, 1, 7), Open("5,1")) == null, "path: a blocked goal tile has no way");
            check(PathFinder.Find(from, new Pos(5, 1, 6), Open()) == null, "path: another floor has no way");
            check(PathFinder.Find(from, from, Open()).Count == 0, "path: already there is an empty path");
            // a range goal (the walk-up to an NPC): stop within 3 tiles, never on the target tile
            var up = PathFinder.Find(from, new Pos(9, 1, 7), Open(), 3);
            var end = PathFinder.Tiles(from, up).Last();
            check(up != null && up.Count == 5 && PathFinder.Cheb(end, new Pos(9, 1, 7)) == 3, "path: a range goal stops at the edge of the range");
            check(PathFinder.Find(from, new Pos(3, 1, 7), Open(), 3).Count == 0, "path: already in range is an empty path");
            // the path never leaves the walkable tiles
            var any = PathFinder.Find(from, new Pos(10, 10, 7), Open("2,1", "1,2", "2,2", "5,5", "5,6", "6,5"));
            check(any != null && PathFinder.Tiles(from, any).Skip(1).All(p => Open("2,1", "1,2", "2,2", "5,5", "5,6", "6,5")(p)), "path: every tile of the path is walkable");
            // nothing explored: the node limit ends the search
            check(PathFinder.Find(from, new Pos(11, 11, 7), p => true, 0, 10) == null, "path: the node limit stops a long search");
        }

        static void Packets(Action<bool, string> check)
        {
            var codes = new Dictionary<Dir, byte> { { Dir.East, 1 }, { Dir.NorthEast, 2 }, { Dir.North, 3 }, { Dir.NorthWest, 4 }, { Dir.West, 5 }, { Dir.SouthWest, 6 }, { Dir.South, 7 }, { Dir.SouthEast, 8 } };
            check(codes.All(kv => WalkDirs.Code(kv.Key) == kv.Value), "autowalk: the direction bytes are the protocol's");
            check(Hex(AutoWalkPackets.WalkPacket(new List<Dir> { Dir.East, Dir.East, Dir.North })) == "6403010103", "autowalk: 0x64, count, steps in walking order");
            check(AutoWalkPackets.WalkPacket(new List<Dir>()) == null, "autowalk: an empty path sends nothing");
            var longPath = Enumerable.Repeat(Dir.South, 150).ToList();
            var pk = AutoWalkPackets.WalkPacket(longPath);
            check(pk.Length == 2 + AutoWalkPackets.MaxSteps && pk[1] == AutoWalkPackets.MaxSteps, "autowalk: a long path is cut at 100 steps");
            check(Hex(AutoWalkPackets.StopPacket()) == "be", "autowalk: stop is 0xBE");
            check(WalkDirs.Step(new Pos(5, 5, 7), Dir.NorthWest) == new Pos(4, 4, 7) && WalkDirs.Step(new Pos(5, 5, 7), Dir.South) == new Pos(5, 6, 7), "autowalk: steps move the tile");
        }

        static void WalkState(Action<bool, string> check)
        {
            var from = new Pos(1, 1, 7);
            var path = new List<Dir> { Dir.East, Dir.East, Dir.East };
            var s = new AutoWalkState();
            check(s.Update(from, 0) == AutoWalkState.Result.None, "autowalk state: idle before a start");
            s.Start(from, path, 0);
            check(s.Active && s.Remaining == 3 && s.Goal == new Pos(4, 1, 7), "autowalk state: starts with the goal at the path's end");
            check(s.Update(new Pos(2, 1, 7), 300) == AutoWalkState.Result.Running && s.Remaining == 2, "autowalk state: following the path is running");
            check(s.Update(new Pos(4, 1, 7), 900) == AutoWalkState.Result.Arrived && !s.Active, "autowalk state: the goal is arrival");
            s.Start(from, path, 0);
            check(s.Update(new Pos(1, 2, 7), 100) == AutoWalkState.Result.Interrupted && !s.Active, "autowalk state: off the path is an interruption (a manual step, a push)");
            s.Start(from, path, 0);
            s.Update(new Pos(2, 1, 7), 100);
            check(s.Update(new Pos(2, 1, 7), 100 + AutoWalkState.StallMs - 1) == AutoWalkState.Result.Running, "autowalk state: a short wait still runs");
            check(s.Update(new Pos(2, 1, 7), 100 + AutoWalkState.StallMs + 1) == AutoWalkState.Result.Stalled, "autowalk state: no progress for too long stalls");
            s.Start(from, path, 0);
            s.Cancel();
            check(!s.Active && s.Update(from, 10) == AutoWalkState.Result.None, "autowalk state: cancel ends it");
        }

        static void WalkMapChecks(Action<bool, string> check)
        {
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            var ground = new ThingType { Ground = true };
            var wall = new ThingType { NotWalkable = true };
            var fire = new ThingType { BlockPath = true };
            Tile Make(int x, params Thing[] things)
            {
                var t = new Tile(new Pos(x, 1, 7));
                t.Things.AddRange(things);
                w.Tiles[t.Pos] = t;
                return t;
            }
            Thing G() => new Thing { Item = new Item { Id = 100, Type = ground } };
            Make(1, G());
            Make(2, G(), new Thing { Item = new Item { Id = 101, Type = wall } });
            Make(3, G(), new Thing { Item = new Item { Id = 102, Type = fire } });
            Make(4, G(), new Thing { Creature = new Creature { Id = 9 } });
            Make(5, G(), new Thing { Creature = new Creature { Id = 10, Walkthrough = true } });
            Make(6, G(), new Thing { Creature = new Creature { Id = 5 } });
            Make(7, new Thing { Item = new Item { Id = 103, Type = new ThingType() } });
            check(WalkMap.Walkable(w, new Pos(1, 1, 7), 5), "walkmap: a ground tile is walkable");
            check(!WalkMap.Walkable(w, new Pos(2, 1, 7), 5), "walkmap: a not walkable item blocks");
            check(!WalkMap.Walkable(w, new Pos(3, 1, 7), 5), "walkmap: a not pathable item (a field) blocks");
            check(!WalkMap.Walkable(w, new Pos(4, 1, 7), 5), "walkmap: a creature blocks");
            check(WalkMap.Walkable(w, new Pos(5, 1, 7), 5), "walkmap: a walk-through creature does not block");
            check(WalkMap.Walkable(w, new Pos(6, 1, 7), 5), "walkmap: the player's own creature does not block");
            check(!WalkMap.Walkable(w, new Pos(7, 1, 7), 5), "walkmap: a tile with no ground is not walkable");
            check(!WalkMap.Walkable(w, new Pos(8, 1, 7), 5), "walkmap: an unknown tile is not walkable");
        }

        static void Bars(Action<bool, string> check)
        {
            var t = new HudBarTrack();
            t.Observe(100, 1000);
            check(t.Shown(1000) == 100 && t.Settled(1000), "bars: the first value is taken at once");
            t.Observe(60, 2000);
            double mid = t.Shown(2000 + HudBarTrack.EaseMs / 2);
            check(mid < 100 && mid > 60, "bars: a fall eases (half way is between the values)");
            check(t.Shown(2000 + HudBarTrack.EaseMs) == 60, "bars: the bar reaches the value exactly");
            check(t.ChipAt(2000 + 100) == 100, "bars: the chip holds where the bar stood");
            check(t.ChipAt(2000 + HudBarTrack.HoldMs + HudBarTrack.SlideMs / 2) < 100 && t.ChipAt(2000 + HudBarTrack.HoldMs + HudBarTrack.SlideMs / 2) > 60, "bars: the chip slides after the hold");
            check(t.ChipAt(2000 + HudBarTrack.HoldMs + HudBarTrack.SlideMs) == 60 && t.Settled(2000 + 1000), "bars: the chip ends at the value and the bar settles");
            t.Observe(90, 5000);
            check(t.Shown(5000 + 10) > 60 && t.Shown(5000 + 10) < 90 && t.Shown(5000 + HudBarTrack.EaseMs) == 90, "bars: a rise eases up");
            double c0 = t.ChipAt(5000 + HudBarTrack.EaseMs);
            check(c0 == 90, "bars: a rise leaves no chip");
            t.Observe(0, 7000);
            t.Observe(50, 7050);   // a new value in mid fall: the chip starts from where the one on screen is
            check(t.ChipAt(7050) >= t.Shown(7050), "bars: the chip is never under the fill");
            // widths: at rest the plain fill width of the plate
            var r = new HudBarTrack();
            r.Observe(50, 0);
            r.Widths(50, 100, 100, 0, out int fill, out int chip, out bool settled);
            check(settled && fill == Plate.FillWidth(50, 100, 100) && chip == fill, "bars: at rest the width is the plate's");
            r.Observe(25, 100);
            r.Widths(25, 100, 100, 100 + 20, out fill, out chip, out settled);
            check(!settled && chip >= fill && fill >= 25 && fill <= 50, "bars: moving, the fill is between the values and the chip is not narrower");
            var again = new HudBarTrack();
            again.Observe(80, 500);
            again.Reset();
            again.Observe(30, 600);
            check(again.Shown(600) == 30, "bars: a reset takes the next value at once");
            check(HudBarTrack.Percent(0, 100) == 0 && HudBarTrack.Percent(100, 100) == 100 && HudBarTrack.Percent(50, 200) == 25 && HudBarTrack.Percent(5, 0) == 0, "bars: percent of a value");
        }

        static void Split(Action<bool, string> check)
        {
            var m = new SplitStackModel(64);
            check(m.Count == 64 && m.Max == 64 && m.Text == "64", "split: starts with the whole stack");
            m.Half();
            check(m.Count == 32, "split: half");
            m.One();
            check(m.Count == 1, "split: one");
            m.Step(-5);
            check(m.Count == 1, "split: never under one");
            m.Step(500);
            check(m.Count == 64, "split: never over the stack");
            m.SetText("12x3");
            check(m.Count == 64, "split: a long number is pulled in to the stack");
            m.SetText("");
            check(m.Text == "" && m.Count == 64, "split: an empty box keeps the count");
            m.SetText("7");
            check(m.Count == 7 && m.PacketCount == 7, "split: typed count");
            m.SetFraction(0f);
            check(m.Count == 1, "split: slider at the start is one");
            m.SetFraction(1f);
            check(m.Count == 64 && Math.Abs(m.Fraction - 1f) < 1e-6, "split: slider at the end is the stack");
            check(new SplitStackModel(500).Max == 100, "split: a stack is at most 100");
            check(new SplitStackModel(1).Fraction == 1f, "split: a single item has a full slider");
            check(SplitStackModel.Asks(true, 5, false) && !SplitStackModel.Asks(true, 1, false) && !SplitStackModel.Asks(false, 5, false) && !SplitStackModel.Asks(true, 5, true), "split: asks for a stackable with more than one, never with Ctrl");
            check(SplitStackModel.Whole(0) == 1 && SplitStackModel.Whole(40) == 40 && SplitStackModel.Whole(900) == 100, "split: the whole stack count stays in 1..100");
            m.Set(7);
            var packet = Protocol.MoveItemPacket(new Pos(65535, 64, 0), 3031, 0, new Pos(65535, 65, 2), m.PacketCount);
            check(packet[packet.Length - 1] == 7, "split: the count is the last byte of the move packet");
        }

        static void Bubble(Action<bool, string> check)
        {
            Func<string, float> measure = s => s.Length * 6f;
            var lines = NpcBubble.Wrap("Welcome to my shop, traveller. I buy and sell all kinds of wares.", 120, measure);
            check(lines.Count >= 3 && lines.All(l => measure(l) <= 120), "bubble: a long reply wraps into lines that fit");
            check(string.Join(" ", lines) == "Welcome to my shop, traveller. I buy and sell all kinds of wares.", "bubble: wrapping loses no word");
            var cut = NpcBubble.Wrap("Supercalifragilisticexpialidocious", 60, measure);
            check(cut.Count >= 3 && cut.All(l => measure(l) <= 60) && string.Concat(cut) == "Supercalifragilisticexpialidocious", "bubble: a word wider than a line is cut by letters");
            check(NpcBubble.Wrap("one\ntwo", 100, measure).Count == 2, "bubble: a new line stays");
            var many = Enumerable.Range(0, 12).Select(i => "line" + i).ToList();
            var vis = NpcBubble.Visible(many);
            check(vis.Count == NpcBubble.MaxLines && vis[0].StartsWith("...") && vis[vis.Count - 1] == "line11", "bubble: the last lines show");
            check(NpcBubble.WidthFor(10, 500) == NpcBubble.MinWidth && NpcBubble.WidthFor(900, 500) == NpcBubble.MaxWidth && NpcBubble.WidthFor(900, 100) == 100, "bubble: the width is between its limits and the room");
            // above the NPC, centred, tail at the NPC; inside the map
            var p = NpcBubble.Place(160, 60, 300, 200, 300, 240, 0, 0, 600, 400);
            check(!p.Below && p.X == 220 && p.Y < 200 && p.TailY == p.Y + 60 - 3, "bubble: above the NPC with the tail on the bottom edge");
            var left = NpcBubble.Place(160, 60, 10, 200, 10, 240, 0, 0, 600, 400);
            check(left.X == 4 && left.TailX >= left.X + 8, "bubble: kept inside the map at the left edge");
            var below = NpcBubble.Place(160, 60, 300, 20, 300, 60, 0, 0, 600, 400);
            check(below.Below && below.Y > 60 - 3 && below.TailY < below.Y, "bubble: under the NPC when there is no room above");
            var tiny = NpcBubble.Place(160, 60, 300, 200, 300, 240, 0, 0, 100, 40);
            check(tiny.X == 4 && tiny.Y >= 4, "bubble: a map smaller than the bubble does not break the place");
            // range and the walk-up
            var me = new Pos(10, 10, 7);
            check(NpcBubble.InRange(me, new Pos(13, 8, 7)) && !NpcBubble.InRange(me, new Pos(14, 10, 7)) && !NpcBubble.InRange(me, new Pos(10, 10, 6)), "bubble: the talk radius is 3 tiles on one floor");
            check(NpcBubble.Keep(true, true, 1000, 0) && !NpcBubble.Keep(false, true, 1000, 0) && !NpcBubble.Keep(true, false, 1000, 0) && !NpcBubble.Keep(true, true, NpcBubble.IdleMs + 1, 0), "bubble: stays while in view, in range and not idle");
            var a = new NpcApproach();
            check(a.Update(true, me, me, 0) == NpcApproach.Step.Idle, "approach: idle before a start");
            a.Start(5, "Yasir", 1000);
            check(a.Update(true, me, new Pos(20, 10, 7), 2000) == NpcApproach.Step.Waiting, "approach: waits while walking");
            check(a.Update(true, new Pos(17, 10, 7), new Pos(20, 10, 7), 3000) == NpcApproach.Step.Greet && !a.Active, "approach: greets in range");
            a.Start(5, "Yasir", 1000);
            check(a.Update(false, me, me, 1500) == NpcApproach.Step.Failed, "approach: the NPC leaving ends it");
            a.Start(5, "Yasir", 1000);
            check(a.Update(true, me, new Pos(20, 10, 7), 1000 + NpcBubble.ApproachTimeoutMs + 1) == NpcApproach.Step.Failed, "approach: gives up after the timeout");
            var path = NpcApproach.PathTo(me, new Pos(18, 10, 7), p2 => true);
            check(path != null && path.Count == 5, "approach: the path ends at the edge of the talk radius");
            check(NpcApproach.PathTo(me, new Pos(18, 10, 7), p2 => false) == null, "approach: no way gives null");
        }

        const string Services = "{\"updated\":1,\"boostedcreature\":{\"creature\":{\"name\":\"Rotworm\",\"outfit\":{\"type\":26,\"head\":1,\"body\":2,\"legs\":3,\"feet\":4,\"addons\":0}},\"boss\":{\"name\":\"Ferumbras\",\"outfit\":{\"type\":229}}},"
            + "\"eventschedule\":{\"eventlist\":[{\"name\":\"Blood Moon\",\"description\":\"+50% experience\",\"colorlight\":\"#a02020\",\"startdate\":{\"date\":\"2026-11-07 00:00:00\"},\"enddate\":{\"date\":\"2026-11-08 23:59:59\"}},"
            + "{\"name\":\"Loot Frenzy\",\"description\":\"\",\"colorlight\":\"#e0b84a\",\"startdate\":{\"date\":\"2026-11-13 00:00:00\"},\"enddate\":{\"date\":\"2026-11-13 23:59:59\"}},"
            + "{\"name\":\"Old\",\"startdate\":{\"date\":\"2026-10-01 00:00:00\"},\"enddate\":{\"date\":\"2026-10-02 00:00:00\"}},{\"name\":\"Bad\",\"startdate\":{\"date\":\"x\"}}]},"
            + "\"cacheinfo\":{\"playersonline\":12,\"online\":\"12 players online\"}}";

        static void Login(Action<bool, string> check)
        {
            var n = LoginNews.Parse(Services);
            check(n.PlayersOnline == 12 && n.Creature != null && n.Creature.Name == "Rotworm" && n.Creature.Outfit.LookType == 26 && n.Creature.Outfit.Body == 2 && n.Boss.Name == "Ferumbras", "login news: players, boosted creature and boss");
            check(n.Events.Count == 3 && n.Events[0].Name == "Old" && n.Events[2].Name == "Loot Frenzy", "login news: events by start, a bad date is dropped");
            var now = new DateTime(2026, 11, 8, 12, 0, 0);
            var up = n.Upcoming(now, 4);
            check(up.Count == 2 && up[0].Name == "Blood Moon" && up[1].Name == "Loot Frenzy", "login news: running first, then the next, past events gone");
            check(LoginNews.DaysUntil(up[0], now) == 0 && LoginNews.DaysUntil(up[1], now) == 5, "login news: days until an event");
            check(n.Upcoming(now, 1).Count == 1, "login news: at most max events");
            var empty = LoginNews.Parse("not json");
            check(empty.PlayersOnline == -1 && empty.Events.Count == 0 && empty.Creature == null, "login news: bad text gives an empty news");
            var st = LoginBar.Of(n, true, false, false, false, false);
            check(st.Bar && st.Info && st.Boost, "login bar: both panels with data");
            check(!LoginBar.Of(empty, true, false, false, false, false).Bar && !LoginBar.Of(n, true, true, false, false, false).Bar && !LoginBar.Of(n, true, false, true, false, false).Bar && !LoginBar.Of(n, false, false, false, false, false).Bar && !LoginBar.Of(n, true, false, false, true, false).Bar, "login bar: no data, splash, no room, no sign-in panel or the character list: no bar");
            check(!LoginBar.Of(LoginNews.Parse("{\"boostedcreature\":{\"creature\":{\"name\":\"Rat\"}}}"), true, false, false, false, false).Info, "login bar: no events, no schedule panel");
            var xs = LoginBar.Row(new float[] { 100, 100 }, new[] { true, true }, 400, 8);
            check(xs[0] == 96 && xs[1] == 204, "login bar: the panels sit side by side, centred");
            var one = LoginBar.Row(new float[] { 100, 100 }, new[] { false, true }, 400, 8);
            check(one[0] == -1 && one[1] == 150, "login bar: a hidden panel leaves the other centred");
            LoginDecor.Medallions(100, 50, 340, false, out float lx, out float ly, out float rx, out float ry);
            check(lx == 68 && rx == 408 && ly == 64 && ry == 64, "login decor: the medallions sit on the panel's side edges");
            LoginDecor.Medallions(100, 50, 340, true, out lx, out ly, out rx, out ry);
            check(lx == 56 && rx == 420, "login decor: on a phone they move out of the fields");
            LoginDecor.Crests(100, 50, 340, 300, out float cx, out float ty, out float by);
            check(cx == 100 + 170 - 48 && ty == 44 && by == 50 + 300 - 22 + 6, "login decor: the crests sit on the top and bottom edge");
            check(SiteUrls.Services("play.cindersofchaos.com") == "https://cindersofchaos.com/clientservices" && SiteUrls.Account("play.example.org") == "https://example.org/chaos_client_api.php", "site urls: the login host's site");
            check(SiteUrls.Services("localhost") == null && SiteUrls.Account("127.0.0.1") == null && SiteUrls.Services("") == null && SiteUrls.Base("bad host!") == null, "site urls: local and odd hosts have none");
        }

        const string AccountBody = "{\"ok\":true,\"token\":\"abc123\",\"expiresIn\":1800,\"account\":{\"slots\":{\"used\":3,\"limit\":5}},\"looks\":{\"Ember\":{\"type\":128,\"head\":78,\"body\":69,\"legs\":58,\"feet\":76,\"addons\":3,\"wings\":4,\"aura\":2,\"shader\":\"Gold\",\"level\":120,\"vocation\":8,\"sex\":1,\"lastLogin\":1000,\"season\":\"S2\"}}}";

        static void Account(Action<bool, string> check)
        {
            var a = AccountApi.Parse(AccountBody);
            check(a.Ok && a.Token == "abc123" && a.ExpiresIn == 1800 && a.SlotsUsed == 3 && a.SlotsLimit == 5, "account api: token, expiry and slots");
            var l = a.Looks["Ember"];
            check(l.Outfit.LookType == 128 && l.Outfit.Wings == 4 && l.Outfit.Aura == 2 && l.Outfit.Shader == "Gold" && l.Level == 120 && l.Vocation == 8 && l.LastLogin == 1000 && l.Season == "S2", "account api: the look of a character");
            var bad = AccountApi.Parse("{\"ok\":false,\"message\":\"Wrong password.\"}");
            check(!bad.Ok && bad.Error == "Wrong password.", "account api: a refusal carries the website's message");
            check(AccountApi.Parse("{\"ok\":false,\"errors\":[\"One\",\"Two\"]}").Error == "One" && AccountApi.Parse("<html>").Error == "no answer", "account api: the first error, or no answer");
            check(AccountApi.LoginRequest("acc", "pw", "n1") == "{\"action\":\"login\",\"account\":\"acc\",\"password\":\"pw\",\"nonce\":\"n1\"}", "account api: the login request");
            check(AccountApi.StateRequest("t") == "{\"action\":\"state\",\"token\":\"t\"}" && AccountApi.LogoutRequest("t") == "{\"action\":\"logout\",\"token\":\"t\"}", "account api: state and logout requests");
            int i = 0;
            string nonce = AccountApi.Nonce(() => i++);
            check(nonce.Length == 32 && nonce.StartsWith("0123456789abcdef0123"), "account api: a 32 digit hex nonce");
            // the card's outfit: the list's look wins, the website adds wings, aura and shader
            var listOutfit = new Outfit(130, 1, 2, 3, 4, 1);
            var merged = CharCardText.Merge(listOutfit, l);
            check(merged.LookType == 130 && merged.Wings == 4 && merged.Aura == 2 && merged.Shader == "Gold" && listOutfit.Wings == 0, "card: the list's look with the website's wings, aura and shader (the list's own object stays)");
            check(CharCardText.Merge(new Outfit(), l).LookType == 128, "card: no look in the list takes the website's");
            check(CharCardText.Merge(listOutfit, null).LookType == 130 && CharCardText.Merge(null, null) == null, "card: no website look keeps the list's");
            // last login words
            int n;
            long now = 10000000;
            check(CharCardText.LastLoginKey(0, now, out n) == "Never played" && CharCardText.LastLoginKey(now - 60, now, out n) == "Last played just now", "card: never played, just now");
            check(CharCardText.LastLoginKey(now - 600, now, out n) == "Last played {0} minutes ago" && n == 10, "card: minutes ago");
            check(CharCardText.LastLoginKey(now - 5000, now, out n) == "Last played an hour ago", "card: an hour ago");
            check(CharCardText.LastLoginKey(now - 3 * 3600, now, out n) == "Last played {0} hours ago" && n == 3, "card: hours ago");
            check(CharCardText.LastLoginKey(now - 100000, now, out n) == "Last played yesterday", "card: yesterday");
            check(CharCardText.LastLoginKey(now - 5 * 86400, now, out n, true) == "{0} days ago" && n == 5, "card: days ago, short");
            check(CharCardText.LastLoginKey(now - 40 * 86400, now, out n) == "Last played on {0}" && n == -1 && CharCardText.DateOf(86400) == "1970-01-02", "card: a date after a month");
            check(CharCardText.SlotsFull(5, 5) && !CharCardText.SlotsFull(3, 5) && !CharCardText.SlotsFull(9, -1), "card: slots full at the limit");
        }

        static void Panels(Action<bool, string> check)
        {
            var tabs = BagPanel.Tabs(name => name == "SkillsWindow" || name == "StoreWindow");
            check(string.Join(",", tabs.Select(t => t.Id)) == "equip,status,shop", "bag panel: a tab shows only when its window exists");
            check(BagPanel.Tabs(name => true).Count == 4 && BagPanel.Tabs(null).Count == 1, "bag panel: all tabs, or the Equip tab alone");
            var widths = BagPanel.TabWidths(new float[] { 30, 30, 60 }, 200);
            check(widths.Sum() <= 200 && widths[2] > widths[0], "bag panel: tab widths share the row by text length");
            var items = new List<KeyValuePair<int, int>> { new KeyValuePair<int, int>(3031, 50), new KeyValuePair<int, int>(3035, 3), new KeyValuePair<int, int>(3043, 2), new KeyValuePair<int, int>(2160, 9) };
            check(BagPanel.Gold(items) == 50 + 300 + 20000, "bag panel: gold is gold, platinum x100, crystal x10000, other items nothing");
            var counts = BagPanel.CoinCounts(items);
            check(counts[0] == 50 && counts[1] == 3 && counts[2] == 2, "bag panel: the coins of each kind");
            check(BagPanel.Gold(new List<KeyValuePair<int, int>>()) == 0 && BagPanel.FigureSize(100, 50) >= 32, "bag panel: no coins, a figure size");

            var s = PartySettings.Load("");
            check(s.Scale == 100 && s.Shown && !s.ShowSelf && s.ShowBuffs && s.ShowNumbers && s.Follow && !s.Locked, "party settings: the defaults");
            s.StepScale(1); s.StepScale(1);
            check(s.Scale == 120, "party settings: scale steps by 10");
            for (int i = 0; i < 10; i++) s.StepScale(1);
            check(s.Scale == 150, "party settings: scale is at most 150");
            for (int i = 0; i < 20; i++) s.StepScale(-1);
            check(s.Scale == 70, "party settings: scale is at least 70");
            s.ShowBuffs = false; s.Locked = true; s.ShowSelf = true; s.Follow = false;
            var back = PartySettings.Load(s.ToJson());
            check(back.Scale == 70 && !back.ShowBuffs && back.Locked && back.ShowSelf && !back.Follow && back.ShowNumbers && back.Shown, "party settings: saved and loaded");
            check(PartySettings.Load("{\"scale\":93,\"locked\":\"yes\"}").Scale == 90 && !PartySettings.Load("{\"scale\":93,\"locked\":\"yes\"}").Locked, "party settings: scale rounds to a step, a wrong type takes the default");
            check(PartySettings.Load("{\"scale\":900}").Scale == 150 && PartySettings.Load("not json").Scale == 100, "party settings: a wild scale is pulled in, bad text gives the defaults");
            var cfg = new PartySettings();
            var me = new PartyMember { Id = 1, Name = "Me", Flags = PartyMember.FlagSelf };
            var ally = new PartyMember { Id = 2, Name = "Ally" };
            ally.Buffs.Add(new PartyBuff { Icon = "haste", Name = "Haste", EndsAt = 5000 });
            check(cfg.Visible(new[] { me, ally }).Count == 1 && cfg.Visible(new[] { me, ally })[0].Id == 2, "party settings: without myself by default");
            cfg.ShowSelf = true;
            check(cfg.Visible(new[] { me, ally }).Count == 2, "party settings: with myself on");
            check(cfg.FrameHeight(ally) == 60 && cfg.FrameHeight(me) == 44, "party settings: a frame with buffs is 16 taller");
            cfg.ShowBuffs = false;
            check(cfg.FrameHeight(ally) == 44 && !cfg.BuffsShown(ally), "party settings: no buffs row with the option off");
            cfg.ShowBuffs = true; cfg.Scale = 150;
            check(cfg.FrameHeight(ally) == 90 && cfg.Scaled(200) == 300, "party settings: the scale grows a frame");
            ally.Far = true;
            check(!cfg.BuffsShown(ally), "party settings: a far member shows no buffs");
            check(PartySettings.BuffLabel(new PartyBuff { Name = "Magic Shield" }) == "MS" && PartySettings.BuffLabel(new PartyBuff { Name = "haste" }) == "H" && PartySettings.BuffLabel(new PartyBuff { Icon = "stun" }) == "S", "party settings: buff labels are initials");
            check(PartySettings.SecondsLeft(new PartyBuff { EndsAt = 5000 }, 1500) == 4 && PartySettings.SecondsLeft(new PartyBuff { EndsAt = 0 }, 0) == -1 && PartySettings.SecondsLeft(new PartyBuff { EndsAt = 1000 }, 3000) == 0, "party settings: seconds left of a buff");
        }

        static void Texts(Action<bool, string> check)
        {
            string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Client", "Assets", "Chaos"));
            if (!Directory.Exists(root)) { check(true, "phase 6 V texts: sources not found, skipped"); return; }
            var keys = new HashSet<string>();
            var pat = new Regex("Loc\\.T\\(\\s*(\"(?:[^\"\\\\]|\\\\.)*\")");
            foreach (string f in new[] { "Unity/ChaosApp.Phase6V.cs", "Unity/ChaosApp.Plate.cs", "Unity/ChaosApp.CharSelect.cs", "Unity/Windows/EquipmentWindow.cs", "Unity/Windows/PartyFramesWindow.cs" })
                foreach (Match m in pat.Matches(File.ReadAllText(Path.Combine(root, f))))
                    keys.Add(m.Groups[1].Value.Substring(1, m.Groups[1].Value.Length - 2).Replace("\\\"", "\""));
            foreach (var t in BagPanel.AllTabs) keys.Add(t.Text);
            foreach (string k in new[] { "never played", "just now", "{0} minutes ago", "an hour ago", "{0} hours ago", "yesterday", "{0} days ago", "{0}" }) keys.Add(k);
            var missing = keys.Where(k => !LocStrings.PtBr.ContainsKey(k)).ToList();
            check(missing.Count == 0, "phase 6 V texts: every text has a pt-BR entry; missing: " + string.Join(" | ", missing.Take(8)));
            var bad = LocPhase6V.PtBr.Where(kv => Regex.Matches(kv.Key, "\\{\\d\\}").Count != Regex.Matches(kv.Value, "\\{\\d\\}").Count).Select(kv => kv.Key).ToList();
            check(bad.Count == 0, "phase 6 V texts: placeholders match: " + string.Join(" | ", bad.Take(5)));
            check(!LocPhase6V.PtBr.Any(kv => kv.Value.Contains("—") || kv.Value.Contains("–")), "phase 6 V texts: no long dashes in the pt-BR texts");
            Loc.Set("pt-BR");
            check(Loc.T("Move how many?") == "Mover quantos?" && Loc.T("{0} days ago", 3) == "há 3 dias", "phase 6 V texts: pt-BR through Loc.T");
            Loc.Set("en");
        }
    }
}
