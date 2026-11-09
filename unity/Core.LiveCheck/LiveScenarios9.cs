// Phase 29: the first fight of the player's live smoke run, proven on a real server (O433, unity/README.md "New player first fight"). The state machine, the route and the pass rules are
// Core/LiveSmoke.cs (LiveFirstFightStep); the Unity player runs its actions on the app (Unity/ChaosApp.LiveFight.cs), this scenario runs the same actions on a plain GameSession, so
// the route from the temple to the cave, the click-to-walk path (PathFinder over WalkMap.Walkable, one 0x64 packet, AutoWalkState), the Helper engine casting with the player's attack,
// the kill and the body in the container list are proven against the real map, spawns and engine. What only a screen shows (the Helper window's button, the Containers window) is not.
// Opt-in by name (--scenario firstfightsmoke), not in `all`: it is a check of the smoke, not of the game.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using Chaos.Core;

namespace Chaos.Core.LiveCheck
{
    public sealed partial class LiveRun
    {
        /// <summary>Scenarios that run by name only (not in `all`).</summary>
        public static readonly string[] OptInScenarios = { "firstfightsmoke", "purse", "testsummons", "testpets", "testparty", "testpartyxp", "testrift", "testwaystone", "testloot", "testchests", "testspellquest", "testunique", "testdual", "testauto" };

        /// <summary>The time the scenario waits for the state machine: its own limit plus the loot grace and a margin.</summary>
        const int FirstFightSmokeLimitMs = (int)(LiveFirstFightStep.LimitMs + LiveFirstFightStep.LootGraceMs) + 15000;

        void ScFirstFightSmoke(ScenarioResult r)
        {
            var p = s.Parser;
            if (p.Level > 150) { r.Skip("character level " + p.Level + ": the first fight is for a new character (a high level one gets no experience from a Rat)"); return; }
            if (!s.Spells.Loaded) { s.Spells.Open(true); WaitFor(5000, () => s.Spells.Loaded); }
            // the Helper engine the way the Unity window makes it (Windows/HelperWindow.cs Tick)
            var engine = new HelperEngine(s.Spells, new SessionHelperHost(s));
            engine.Reach = s.AutoTargetReach;
            engine.RankOf = s.AutoTargetRank;
            int voc = s.Spells.Vocation != 0 ? s.Spells.Vocation : world.PlayerVocation;
            var result = new LiveFirstFightResult();
            var step = new LiveFirstFightStep(result, Tick);
            var auto = new AutoWalkState();
            int cancels0 = me.Cancels;
            var actions = new List<string>();
            long t0 = Tick;
            var mark = Mark.Of(me);
            var lastState = (LiveFirstFightStep.Phase)(-1);
            int lastRefused = 0;
            while (step.State != LiveFirstFightStep.Phase.Done && s.Closed == null && Tick - t0 < FirstFightSmokeLimitMs)
            {
                Pump(40, () => false);
                engine.Tick();
                auto.Update(me.Pos, s.Now);
                var view = FightView(auto, cancels0, engine);
                if (view.Refused != lastRefused) { r.Note("refused step #" + view.Refused + " at " + ((Tick - t0) / 1000.0).ToString("0.0", CultureInfo.InvariantCulture) + " s, the character at " + P(me.Pos) + ", walk active " + auto.Active + ", state " + step.State + ", things at the stair [" + string.Join(" ", (world.Get(LiveFirstFightStep.Stair)?.Things ?? new List<Thing>()).Select(th => th.IsCreature ? "c" + th.Creature.Id : th.Item.Id.ToString(CultureInfo.InvariantCulture))) + "]"); lastRefused = view.Refused; }
                var act = step.Update(Tick, view);
                if (step.State != lastState) { lastState = step.State; actions.Add(step.State + "@" + ((Tick - t0) / 1000.0).ToString("0.0", CultureInfo.InvariantCulture) + "s " + P(me.Pos)); }
                switch (act)
                {
                    case LiveFightAction.PressAutoSetup:
                        {
                            string m = engine.AutoSetup(voc);
                            if (m != null) engine.AutoSupport();
                            step.AutoSetupDone(engine.Config.Shooter.Count(x => x.Id > 0), m ?? "");
                            r.Note("Auto setup: " + (m ?? "no rotation") + "; " + engine.Config.Shooter.Count(x => x.Id > 0) + " slot(s), healing rows " + engine.Config.Heals.Count(h => h.Id != 0));
                            break;
                        }
                    case LiveFightAction.HelperOn:
                        engine.Config.Enabled = true;
                        engine.Config.MagicShooter = true;
                        step.HelperSet(engine.Config.Enabled, engine.Config.MagicShooter);
                        break;
                    case LiveFightAction.Walk:
                        {
                            uint self = world.PlayerId;
                            var path = PathFinder.Find(me.Pos, step.WalkGoal, pp => WalkMap.Walkable(world, pp, self), step.WalkRange);
                            if (path == null) { step.WalkStarted(-1); break; }
                            if (path.Count == 0) { step.WalkStarted(0); break; }
                            if (path.Count > AutoWalkPackets.MaxSteps) path.RemoveRange(AutoWalkPackets.MaxSteps, path.Count - AutoWalkPackets.MaxSteps);
                            s.SendRaw(AutoWalkPackets.WalkPacket(path));
                            auto.Start(me.Pos, path, s.Now);
                            step.WalkStarted(path.Count);
                            break;
                        }
                    case LiveFightAction.Step:
                        // the player's key path: one step in the direction (the stair is no tile the click path takes)
                        WaitFor(1500, () => s.CanWalk || s.Closed != null);
                        s.Walk(step.StepDir);
                        break;
                    case LiveFightAction.ChaseOn:
                        s.SetFightModes(new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = true });
                        break;
                    case LiveFightAction.Attack: s.Attack(step.AttackId); break;
                    case LiveFightAction.UseLoot: s.UseItem(step.Loot.Tile, (ushort)step.Loot.ItemId, (byte)step.Loot.Stack); break;
                    case LiveFightAction.OpenContainers: break;
                    case LiveFightAction.Screenshot: step.ShotTaken("(no screen)"); break;
                }
            }
            r.Note("states: " + string.Join(", ", actions));
            r.Note("walk: " + result.Hops + " hop(s), " + result.Replans + " re-plan(s), " + result.WalkPlanned + " step(s) planned, " + result.WalkSent + " sent, " + result.WalkConfirmed + " confirmed, " + result.WalkRefused + " refused; cave reached " + result.ReachedCave);
            r.Note("fight: " + result.Kills + " kill(s) of a " + (result.Monster.Length > 0 ? result.Monster : "(none)") + ", experience " + result.ExpBefore + " to " + result.ExpAfter + " (" + result.ExpTexts + " text(s)), health " + p.Health + "/" + p.MaxHealth + "; Helper " + (result.HelperOn ? "on" : "off") + ", rotation " + (result.RotationOn ? "on" : "off") + "");
            r.Note("body: " + (result.LootOpened ? "opened, '" + result.LootName + "' with " + result.LootItems + " item(s)" : result.LootTried ? "tried, never opened" : "no container on the kill's tile") + ", open containers [" + string.Join(" ", p.Containers.Values.Select(c => c.Id + ":" + c.ItemId + ":" + c.Name)) + "]");
            foreach (var h in result.HopLog) r.Note("hop: " + h);
            foreach (var w in result.Warnings()) r.Note("warning: " + w);
            r.Note("block: " + result.ToJson(null));
            var problems = new StringBuilder();
            foreach (var f in result.Failures()) problems.Append(f).Append("; ");
            if (step.State != LiveFirstFightStep.Phase.Done) problems.Append("the state machine did not finish (state " + step.State + ", the character at " + P(me.Pos) + "); ");
            if (p.Failures.Count(x => x.Unknown) > 0) problems.Append("an unknown packet type came; ");
            // what a player meets at the end: the logout after a fight (the server refuses it in the minute after a fight)
            if (s.Closed == null)
            {
                s.Logout();
                bool closed = WaitFor(4000, () => s.Closed != null);
                r.Note("logout right after the fight: " + (closed ? "the server closed the connection" : "no close in 4 s (refused in a fight): the app drops the connection"));
            }
            if (problems.Length > 0) { r.Fail(problems.ToString().Trim()); return; }
            if (result.Skipped) { r.Skip(result.SkipReason); return; }
            r.Pass("Auto setup " + result.AutoSetupSlots + " slot(s), Helper on, " + result.Hops + " hop(s) from the temple to the cave, " + result.Kills + " " + result.Monster + " killed (" + result.ExpBefore + " to " + result.ExpAfter + " experience), body " + (result.LootOpened ? "opened with " + result.LootItems + " item(s)" : "not opened") + ", in " + (result.Ms / 1000).ToString("0", CultureInfo.InvariantCulture) + " s");
        }

        LiveFightView FightView(AutoWalkState auto, int cancels0, HelperEngine engine)
        {
            var p = s.Parser;
            var v = new LiveFightView
            {
                Player = me.Pos,
                Dead = p.Dead,
                Health = p.Health,
                MaxHealth = p.MaxHealth,
                SpellsLoaded = s.Spells.Loaded,
                AutoWalkActive = auto.Active,
                Moves = p.PlayerMoves,
                Refused = me.Cancels - cancels0,
                ExpTexts = p.ExpGainTexts,
                Experience = (long)p.Experience,
                ContainerOpens = Seen(0x6E),
                ContainerCloses = Seen(0x6F),
                ContainersWindowOpen = p.Containers.Count > 0,
            };
            uint self = world.PlayerId;
            v.Walkable = pp => WalkMap.Walkable(world, pp, self);
            foreach (var c in world.Creatures.Values)
                if (c.Type == 1 && c.Position.X > 0 && c.Position.Z == v.Player.Z)
                    v.Monsters.Add(new LiveFightMonster { Id = c.Id, Name = c.Name, Pos = c.Position, HealthPercent = c.HealthPercent });
            v.LootNear = at => LiveFirstFightStep.LootOn(world, at);
            foreach (var kv in p.Containers)
                v.Containers.Add(new LiveFightContainer { Id = kv.Key, ItemId = kv.Value.ItemId, Name = kv.Value.Name ?? "", Items = kv.Value.Items.Count(i => i != null) });
            return v;
        }
    }
}
