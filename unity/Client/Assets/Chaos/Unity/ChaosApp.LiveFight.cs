// The first fight of the live smoke run (O433, unity/README.md "New player first fight"): after the Helper shot the fresh character plays its first fight the way a player would. The state
// machine, the route and the pass rules are Core/LiveSmoke.cs (LiveFirstFightStep, tested without Unity); this file is what runs its actions on the app:
//   PressAutoSetup  the Helper window's own Auto setup (HelperWindow.PressAutoSetup: the code the button runs), the window opened as a player has it
//   HelperOn        the window's "Helper on" and "Spell rotation" ticks (HelperWindow.SetHelperOn / SetSpellRotation)
//   Walk            the client's click to walk: the path over the tiles WalkMap.Walkable calls free (PathFinder, ChaosApp.StartAutoWalk), sent as one 0x64 packet, the server walks it
//   ChaseOn         the Fight window's chase mode (the 0xA0 mode packet)
//   Attack          the attack order of a click on the Rat (GameSession.Attack)
//   UseLoot         the plain right click on the body (ChaosApp.RightClickItem: use, with the free container id), the container opens in the Containers window
//   ShowBody        the Helper window is closed and the Containers window comes to the front (they share the right side of the screen), so the picture shows the open body
//   Screenshot      first_fight_IDENTITY.png: the fight, or the open body
// SmoothWalk.cs, WalkTour.cs and the walking video are not touched: the route is not the key path, it is the click path. Nothing here stops the run: a fault is a line of the "firstfight" block.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        sealed partial class LiveSmokeDirector
        {
            LiveFirstFightStep ffStep;
            int fightCancels, fightKey, fightKeySent0;
            double fightKeyAt;
            LiveFirstFightStep.Phase ffLogged = LiveFirstFightStep.Phase.Spells;
            bool ffLoggedAny;

            /// <summary>Counts the steps the server refuses on the fresh character's session (the normal character's session is hooked by HookSession; the fresh one is not, so its opcodes do not count as prefetch).</summary>
            void HookFightCancels()
            {
                var p = app.session.Parser;
                var prev = p.WalkCancelled;
                p.WalkCancelled = d => { fightCancels++; prev(d); };
            }

            /// <summary>After the Helper shot: the fresh character's first fight. The Helper window is opened the way a player has it (on its Shooter tab, where Auto setup is).</summary>
            void BeginFirstFight()
            {
                ffStep = new LiveFirstFightStep(rep.FirstFight, NowMs);
                ffLoggedAny = false;
                var win = app.FindWindow<HelperWindow>();
                if (win != null) { win.Open = true; win.RaiseNext = true; }
                Debug.Log("chaos live smoke: first fight: started");
                SetPhase(Phase.FirstFight);
            }

            void StepFirstFight()
            {
                if (ffStep.State == LiveFirstFightStep.Phase.Done) { FightFinished(); return; }
                // the held key goes up when its step is sent (a held key sends one step per frame at most), or after a second
                if (fightKey != 0 && (app.session.WalksSent > fightKeySent0 || NowMs - fightKeyAt > 1000)) fightKey = 0;
                var view = BuildFightView();
                var act = ffStep.Update(NowMs, view);
                if (!ffLoggedAny || ffStep.State != ffLogged)
                {
                    ffLoggedAny = true; ffLogged = ffStep.State;
                    Debug.Log("chaos live smoke: first fight: " + ffStep.State + " at " + Math.Round(rep.FirstFight.Ms / 1000.0, 1).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + " s, the character at " + view.Player);
                }
                switch (act)
                {
                    case LiveFightAction.PressAutoSetup:
                        {
                            var win = app.FindWindow<HelperWindow>();
                            if (win == null) { ffStep.AutoSetupDone(0, "no Helper window"); break; }
                            win.Open = true; win.RaiseNext = true;
                            string m = win.PressAutoSetup(app);
                            ffStep.AutoSetupDone(win.FilledSlots(), m ?? "");
                            Debug.Log("chaos live smoke: first fight: Auto setup filled " + win.FilledSlots() + " of the 5 slots");
                            break;
                        }
                    case LiveFightAction.HelperOn:
                        {
                            var win = app.FindWindow<HelperWindow>();
                            if (win == null) break;
                            win.SetHelperOn(true);
                            win.SetSpellRotation(true);
                            ffStep.HelperSet(win.HelperOn, win.SpellRotationOn);
                            break;
                        }
                    case LiveFightAction.Walk: ffStep.WalkStarted(ClickWalk(ffStep.WalkGoal, ffStep.WalkRange)); break;
                    case LiveFightAction.Step:
                        // the player's key path (WalkMaskSource, WalkInputState, GameSession.Walk): the key is held until the step is sent, as the walk part of the run does
                        fightKey = LiveWalker.MaskOf(ffStep.StepDir);
                        fightKeySent0 = app.session.WalksSent;
                        fightKeyAt = NowMs;
                        app.WalkMaskSource = () => fightKey;
                        break;
                    case LiveFightAction.ChaseOn:
                        app.session.SetFightModes(new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = true });
                        break;
                    case LiveFightAction.Attack: app.session.Attack(ffStep.AttackId); break;
                    case LiveFightAction.UseLoot: UseBody(ffStep.Loot); break;
                    case LiveFightAction.OpenContainers:
                        {
                            var cw = app.FindWindow<ContainersWindow>();
                            if (cw != null) cw.Open = true;
                            break;
                        }
                    case LiveFightAction.ShowBody:
                        {
                            // the Helper window sits over the Containers window (both on the right): the player closes it, the body shows
                            var hw = app.FindWindow<HelperWindow>();
                            if (hw != null) hw.Open = false;
                            var cw = app.FindWindow<ContainersWindow>();
                            if (cw != null) { cw.Open = true; cw.RaiseNext = true; }
                            break;
                        }
                    case LiveFightAction.Screenshot:
                        {
                            string name = "first_fight_" + cfg.Identity + ".png";
                            LogFightResult();
                            RequestShot(name, () => { ffStep.ShotTaken(name); FightFinished(); });
                            break;
                        }
                }
            }

            void FightFinished() { app.WalkMaskSource = null; BeginNewLogout(); }

            void LogFightResult()
            {
                var r = rep.FirstFight;
                var inv = System.Globalization.CultureInfo.InvariantCulture;
                Debug.Log("chaos live smoke: first fight: " + (r.Skipped ? "skipped: " + r.SkipReason : "Auto setup " + r.AutoSetupSlots + " slots, Helper " + (r.HelperOn ? "on" : "OFF") + ", walk " + r.WalkPlanned + " planned " + r.WalkSent + " sent "
                    + r.WalkConfirmed + " confirmed " + r.WalkRefused + " refused, " + r.Kills + " kill(s)" + (r.Kills > 0 ? " of a " + r.Monster + ", experience " + r.ExpBefore + " to " + r.ExpAfter : "")
                    + ", body " + (r.LootOpened ? "opened with " + r.LootItems + " item(s)" : "not opened")) + ", " + Math.Round(r.Ms / 1000.0, 1).ToString("0.0", inv) + " s");
                foreach (var f in r.Failures()) Debug.Log("chaos live smoke: first fight: failure: " + f);
            }

            /// <summary>The client's click to walk: the same path a quick click on the map starts (PathFinder over WalkMap.Walkable, one 0x64 packet, the auto-walk state of the app). Returns the steps planned,
            /// 0 when the character is there already, -1 when there is no way over the tiles the client knows.</summary>
            int ClickWalk(Pos goal, int range)
            {
                var me = app.world.Player.Position;
                uint self = app.world.PlayerId;
                var world = app.world;
                var path = PathFinder.Find(me, goal, p => WalkMap.Walkable(world, p, self), range);
                if (path == null) return -1;
                if (path.Count == 0) return 0;
                app.npcApproach.Cancel();
                return app.StartAutoWalk(me, goal, range) ? Math.Min(path.Count, (int)AutoWalkPackets.MaxSteps) : -1;
            }

            /// <summary>The plain right click on the body: ChaosApp.RightClickItem (use it, with the free container id), as a click on the tile does.</summary>
            void UseBody(LiveFightLoot loot)
            {
                var t = app.world.Get(loot.Tile);
                if (t == null || loot.Stack < 0 || loot.Stack >= t.Things.Count || t.Things[loot.Stack].IsCreature) return;
                var item = t.Things[loot.Stack].Item;
                // a body is opened with a plain use, which is what the right click of a container does. The right click of an item the dat flags as multi-use starts a "Use with" crosshair
                // instead and sends nothing (RightClickItem): for a body that is the menu's "Open" entry, so the smoke sends the use itself (CI run 42670112065: the Chaos body never opened)
                if (item != null && item.Type != null && item.Type.Container) app.session.UseItem(loot.Tile, (ushort)item.Id, (byte)loot.Stack, ItemSlots.FreeContainerId(app));
                else app.RightClickItem(new ItemRef(loot.Tile, (byte)loot.Stack, item));
            }

            LiveFightView BuildFightView()
            {
                var s = app.session;
                var p = s.Parser;
                var w = app.world;
                var v = new LiveFightView
                {
                    Player = w.Player.Position,
                    Dead = p.Dead,
                    Health = p.Health,
                    MaxHealth = p.MaxHealth,
                    SpellsLoaded = s.Spells.Loaded,
                    AutoWalkActive = app.autoWalk.Active,
                    Moves = p.PlayerMoves,
                    Refused = fightCancels,
                    ExpTexts = p.ExpGainTexts,
                    Experience = (long)p.Experience,
                    ContainerOpens = p.Seen.TryGetValue(0x6E, out int opened) ? opened : 0,
                    ContainerCloses = p.Seen.TryGetValue(0x6F, out int closed) ? closed : 0,
                };
                uint self = w.PlayerId;
                v.Walkable = pos => WalkMap.Walkable(w, pos, self);
                foreach (var c in w.Creatures.Values)
                    if (c.Type == 1 && c.Position.X > 0 && c.Position.Z == v.Player.Z)
                        v.Monsters.Add(new LiveFightMonster { Id = c.Id, Name = c.Name, Pos = c.Position, HealthPercent = c.HealthPercent });
                v.LootNear = at => LiveFirstFightStep.LootOn(w, at);
                foreach (var kv in p.Containers)
                {
                    int held = 0;
                    foreach (var it in kv.Value.Items) if (it != null) held++;
                    v.Containers.Add(new LiveFightContainer { Id = kv.Key, ItemId = kv.Value.ItemId, Name = kv.Value.Name ?? "", Items = held });
                }
                var cw = app.FindWindow<ContainersWindow>();
                v.ContainersWindowOpen = cw != null && cw.Open;
                return v;
            }
        }
    }
}
