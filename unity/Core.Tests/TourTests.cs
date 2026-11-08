// The demo tour's fake game server (Core/DemoTour.cs): a real client session logs in to it through the login port and the game port
// (RSA, XTEA, guard challenge), walks the planned steps and watches the scripted timeline on a simulated 60 fps clock. Deterministic:
// the script runs on the clock the loop feeds, never the wall clock.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;

namespace Chaos.Core.Tests
{
    static class TourTests
    {
        public static void Run(Action<bool, string> check)
        {
            var demo = Hd2dDemo.Synthetic();
            var art = TourArt.FromDemo(DemoIds.Synthetic()).Probe(demo.Dat);
            using (var server = new FakeGameServer(art))
            {
                // the map is a function of the tile, with walkable ground on the planned route and a pond or walls where the art has them
                var map = server.Map;
                var step = server.Start;
                bool route = true;
                foreach (var d in TourPlan.Walk)
                {
                    step = step.Offset(d == Dir.East ? 1 : d == Dir.West ? -1 : 0, d == Dir.South ? 1 : d == Dir.North ? -1 : 0);
                    if (!map.Walkable(step.X, step.Y)) route = false;
                }
                check(route, "tour map: the planned walk is on bare ground");
                check(map.Ground(100, 100) == art.Path && map.Ground(95, 100) == art.Grass && map.Item(103, 95) != 0, "tour map: path, grass and the ruin wall");
                check(map.Item(110, 103) == map.Item(110, 103) && map.Ground(110, 103) == map.Ground(110, 103), "tour map: the same tile every time");
                check(server.ScriptEvents > 30, "tour script: " + server.ScriptEvents + " events");

                server.Begin();
                // a slow login client (a player under software GL) must not be taken for a game client: the login port never sends the game challenge
                using (var slow = new System.Net.Sockets.TcpClient("127.0.0.1", server.Port))
                {
                    System.Threading.Thread.Sleep(1200);
                    check(slow.Available == 0 && server.GamePort != server.Port, "tour server: a login client silent for 1.2 s gets no game challenge");
                }
                var res = LoginClient.Login("127.0.0.1", server.Port, "demo", "demo", server.RsaModulus, 30).GetAwaiter().GetResult();
                check(res.Error == null && res.SessionKey == "demo\ndemo\n\n0" && res.Characters.Count == 1 && res.Characters[0].Name == FakeGameServer.HeroName &&
                      res.Characters[0].Vocation == FakeGameServer.HeroVocation && res.Characters[0].Port == server.GamePort, "tour server: login port answers with one character (" + res.Error + ")");
                if (res.Error != null || res.Characters.Count == 0) return;

                double clock = 0;
                GameSession.TestClock = () => clock;
                try
                {
                    var world = new World(demo.Dat);
                    world.Fx.Enabled = true;
                    var session = new GameSession(world, new GameSession.Options
                    {
                        Host = "127.0.0.1", Port = server.GamePort, Account = "demo", Password = "demo", SessionKey = res.SessionKey, Character = FakeGameServer.HeroName,
                        GuardKey = server.GuardKey, Build = 30, RsaModulus = server.RsaModulus, Identity = ClientIdentity.Extended,
                    });
                    session.Start();
                    var wall = DateTime.UtcNow.AddSeconds(20);
                    while (DateTime.UtcNow < wall && !server.InGame) { session.Poll(); Thread.Sleep(5); }
                    check(server.InGame, "tour server: the game port took the login and the guard handshake (" + server.Problem + ")");
                    // settle: the map arrives
                    for (int i = 0; i < 60 && !(session.Parser.LoggedIn && world.Player != null); i++) { clock += 1000.0 / 60; session.Poll(); Thread.Sleep(5); }
                    // the stats can come in a later read than the map (seen on a loaded machine): poll for them without moving the clock
                    var settle = DateTime.UtcNow.AddSeconds(10);
                    while (DateTime.UtcNow < settle && session.Parser.Health != FakeGameServer.MaxHealth) { session.Poll(); Thread.Sleep(5); }
                    check(session.Parser.LoggedIn && world.Player != null && world.Player.Position == server.Start && world.Player.Name == FakeGameServer.HeroName,
                          "tour server: the hero stands on the start tile");
                    check(world.Tiles.Count >= World.ViewW * World.ViewH && world.Creatures.Count == 5, "tour server: the map and five creatures (" + world.Creatures.Count + ")");
                    check(session.Parser.Health == FakeGameServer.MaxHealth && session.Parser.Level == FakeGameServer.HeroLevel, "tour server: stats");

                    double t0 = clock;
                    int walked = 0, effects = 0, missiles = 0, numbers = 0, expNumbers = 0, heals = 0, minHp = int.MaxValue;
                    bool furySeen = false, shopSeen = false, tradeItems = false, attackedSkeleton = false, attackedGhoul = false, said = false, closedShop = false;
                    var toasts = new HashSet<string>();
                    while (clock - t0 < TourPlan.Total)
                    {
                        clock += 1000.0 / 60;
                        double t = clock - t0;
                        session.Poll();
                        while (world.Fx.TryDequeue(out var fx))
                        {
                            if (fx.Kind == FxKind.Effect) effects++;
                            else if (fx.Kind == FxKind.Missile) missiles++;
                            else if (fx.Kind == FxKind.Number)
                            {
                                numbers++;
                                if (fx.Id == 26) expNumbers++;
                                if (fx.Id == 25) heals++;
                            }
                        }
                        foreach (var toast in session.Hud.Toasts.Active.Concat(session.Hud.Toasts.Queue)) toasts.Add(toast.Type);
                        minHp = Math.Min(minHp, session.Parser.Health);
                        if (session.Hud.Buffs.Buffs.ContainsKey("fury")) furySeen = true;
                        // the player's side of the plan, as the director does it
                        if (t >= TourPlan.WalkFrom && walked < TourPlan.Walk.Length && session.CanWalk) { session.Walk(TourPlan.Walk[walked]); walked++; }
                        if (!attackedSkeleton && t >= TourPlan.AttackSkeleton) { session.Attack(FakeGameServer.SkeletonId); attackedSkeleton = true; }
                        if (!attackedGhoul && t >= TourPlan.AttackGhoul) { session.Attack(FakeGameServer.GhoulId); attackedGhoul = true; }
                        if (!said && t >= TourPlan.SayHi) { session.SayToNpc("hi"); said = true; }
                        if (session.Parser.Trade.Open) { shopSeen = true; tradeItems = session.Parser.Trade.Items.Count == 5; }
                        if (shopSeen && !closedShop && t >= TourPlan.ShopCloses) { session.NpcClose(); closedShop = true; }
                        server.Advance(t);
                        Thread.Sleep(3);
                    }
                    for (int i = 0; i < 30; i++) { clock += 1000.0 / 60; session.Poll(); Thread.Sleep(5); }
                    int spellsAtEnd = session.Spells.Spells.Count, partyMembers = session.Party.Members.Count, buffs = session.Hud.Buffs.Buffs.Count;

                    check(walked == TourPlan.Walk.Length && server.Steps == walked && server.Blocked == 0, "tour script: the planned steps were taken (" + server.Steps + " of " + walked + ", blocked " + server.Blocked + ")");
                    check(world.Player.Position == server.HeroPos && server.HeroPos != server.Start, "tour script: the hero ended at " + server.HeroPos + " and the client agrees");
                    check(!server.HasMob(FakeGameServer.SkeletonId) && !server.HasMob(FakeGameServer.GhoulId) && server.HasMob(FakeGameServer.ArcherId) && server.HasMob(FakeGameServer.NpcId),
                          "tour script: the skeleton and the ghoul fell, the archer and the NPC stand");
                    int onMap = world.Tiles.Values.Sum(tile => tile.Things.Count(th => th.Creature != null && (th.Creature.Id == FakeGameServer.SkeletonId || th.Creature.Id == FakeGameServer.GhoulId)));
                    check(onMap == 0 && world.Tiles.Values.Sum(tile => tile.Things.Count(th => th.Creature != null)) == 3, "tour script: the client took them off the map too (" + onMap + " left)");
                    check(effects >= 12 && missiles == 4 && numbers >= 20 && expNumbers == 2 && heals == 1, "tour script: effects " + effects + ", missiles " + missiles + ", numbers " + numbers + ", exp " + expNumbers + ", heals " + heals);
                    check(minHp < FakeGameServer.MaxHealth - 200 && session.Parser.Health > minHp, "tour script: the hero took damage (" + minHp + ") and healed (" + session.Parser.Health + ")");
                    check(server.Attacks == 2 && server.AttackTarget == FakeGameServer.GhoulId && server.Says == 1, "tour server: two attacks and the greeting arrived (" + server.Attacks + ", " + server.Says + ", '" + server.LastSay + "')");
                    check(shopSeen && tradeItems && !session.Parser.Trade.Open, "tour script: the shop opened with five rows and closed");
                    check(session.Parser.NpcTalk.Lines.Any(l => l.FromNpc && l.Text.StartsWith("Greetings")), "tour script: the NPC line");
                    check(spellsAtEnd == 10 && session.Spells.Loaded, "tour script: the spell list (" + spellsAtEnd + ")");
                    check(partyMembers == 3 && session.Party.InParty && session.Party.Self != null && session.Party.Self.Name == FakeGameServer.HeroName, "tour script: the party state (" + partyMembers + ")");
                    check(buffs == 3 && furySeen, "tour script: buff bar entries (" + buffs + "), the fury buff came and went (" + furySeen + ")");
                    check(toasts.Contains("JOURNEY") && toasts.Contains("ACHIEVEMENT") && toasts.Contains("PARTY_INVITE") && toasts.Contains("SEASON_PASS"), "tour script: toasts " + string.Join(",", toasts));
                    check(session.Parser.Talks.LogTab.Lines.Any(l => l.Text.StartsWith("Loot of a skeleton")) && session.Parser.Talks.LogTab.Lines.Any(l => l.Text.StartsWith("Loot of a ghoul")), "tour script: loot lines in the log");
                    check(server.Finished && server.ExtRequests.Count > 0, "tour server: the whole script played; the client asked for " + string.Join(",", server.ExtRequests.Keys.OrderBy(k => k)));
                    session.Dispose();
                }
                finally { GameSession.TestClock = null; }
            }
        }
    }
}
