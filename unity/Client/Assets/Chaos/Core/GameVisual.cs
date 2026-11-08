// The visual, audio and layout models of one session (phase 5, track R), built once with the extended opcode layer and driven by the combat feed and the world:
// sound cues, the region music, level-up wings, chest and Templar auras, cosmetic prints, combat decals, loot beams, ground rings, hit flashes, screen shake and
// name shaders. Core/Audio.cs, Visual.cs and Layout.cs hold the rules. This class only connects them to the parser's events and to World; Unity/ChaosApp.Visual.cs
// plays the cues and draws what is alive. Kept in its own file so the shared GameSession file stays small.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class GroundMark { public Pos Pos; public int Id; public double Born; }
    public sealed class FlashMark { public uint Creature; public double Start, Ms; public bool Red; }
    public sealed class ChestSpot { public Pos Pos; public ChestAuraDef Def; public uint Cursed; }

    public sealed class VisualEffects
    {
        public const double GroundMs = 1200, FlashHold = 300;
        public readonly LevelWingsState Wings;
        public readonly ChestAuraState Aura;
        public readonly CosmeticFxState Cosmetic;
        public readonly NameShaderState Names;
        public readonly DecalField Decals = new DecalField();
        public readonly HitFlasher Flasher = new HitFlasher();
        public readonly ScreenShake Shake = new ScreenShake();
        public readonly SoundMixer Mixer = new SoundMixer();
        public readonly SoundLogic.Hits Hits = new SoundLogic.Hits();
        public readonly MusicState MusicNow = new MusicState();

        // options (the app loads and saves them in PlayerPrefs)
        public SoundSettings Sound = new SoundSettings();
        public MusicSettings Music = new MusicSettings();
        public LootBeamSettings Beams = new LootBeamSettings();
        public VisualFxOptions Fx = new VisualFxOptions();
        public bool DecalsOn = true;

        // what the app plays and draws
        public readonly Queue<SoundPick> Cues = new Queue<SoundPick>();
        public readonly List<GroundMark> Grounds = new List<GroundMark>();
        public readonly List<FlashMark> Flashes = new List<FlashMark>();
        public readonly List<ChestSpot> Chests = new List<ChestSpot>();
        public string Region = "login";
        public bool RegionChanged;
        public string LastCue = "";

        // set by the app: the loot kills (for rare loot sounds), an activity HUD ("arena" or "dungeon"), the rumble clock
        public Func<IList<LootKill>> LootKills = () => null;
        /// <summary>True for a kill whose loot filter rule sound was chosen (the rare-drop cue then stays silent, as the main client's tellGameSound).</summary>
        public Func<int, bool> LootAlerted = k => false;
        public Func<string> Activity = () => null;
        public Func<double> Random = () => 0.5;

        readonly GameSession s;
        World W => s.Parser.W;
        readonly Random rng = new Random(7);
        int lastLevel = -1, lastGoals = -1, lastKillK = int.MinValue;
        double lastScan = -1e9, lastMusic = -1e9;
        readonly Dictionary<uint, Pos> lastPos = new Dictionary<uint, Pos>();
        readonly Dictionary<uint, SeenCreature> seen = new Dictionary<uint, SeenCreature>();

        sealed class SeenCreature { public Pos Pos; public int Health; public byte Type; public string Name = ""; public double At; }

        public VisualEffects(GameSession session)
        {
            s = session;
            var ext = session.Ext;
            Wings = new LevelWingsState(ext) { Clock = () => s.Now, SelfId = () => W.PlayerId };
            Wings.Played = id => Cue("levelup", 0);
            Aura = new ChestAuraState(ext);
            Cosmetic = new CosmeticFxState(ext);
            Names = new NameShaderState(ext);
            W.Fx.Tap = OnFx;
        }

        public void Detach() { if (W.Fx.Tap != null) W.Fx.Tap = null; }

        // ---------------------------------------------------------------------------------------------------- cues
        /// <summary>Asks the mixer for a sound; the pick goes on the cue queue when it plays. dist: tiles from the player.</summary>
        public bool Cue(string key, double dist)
        {
            if (!Mixer.Request(key, s.Now, Sound, out var pick, dist, 1f, n => rng.Next(n))) return false;
            LastCue = key;
            Cues.Enqueue(pick);
            while (Cues.Count > 16) Cues.Dequeue();
            return true;
        }

        public bool DequeueCue(out SoundPick p) { if (Cues.Count == 0) { p = default(SoundPick); return false; } p = Cues.Dequeue(); return true; }

        // ---------------------------------------------------------------------------------------------------- combat feed
        void OnFx(FxEvent e)
        {
            double now = s.Now;
            var me = W.Player;
            switch (e.Kind)
            {
                case FxKind.Effect:
                {
                    string key = SoundLogic.EffectEvent(e.Id, out bool own);
                    if (key != null && me != null && (!own || me.Position == e.Pos)) Cue(key, SoundLogic.Distance(me.Position, e.Pos));
                    if (GroundFx.IsGround(e.Id))
                    {
                        Grounds.Add(new GroundMark { Pos = e.Pos, Id = e.Id, Born = now });
                        while (Grounds.Count > 24) Grounds.RemoveAt(0);
                    }
                    break;
                }
                case FxKind.Number:
                    OnNumber(e, now, me);
                    break;
            }
        }

        void OnNumber(FxEvent e, double now, Creature me)
        {
            int impact = e.Typed ? e.Impact : 0;
            long value = e.Value;
            string snd = SoundLogic.ImpactEvent(e.Id, impact, value, e.Typed);
            if (snd != null) Cue(snd, 0);
            uint target = e.Creature != 0 ? e.Creature : CreatureAt(e.Pos);
            if (e.Id == 23 && target != 0) Hits.Note(target, now);
            // decals: a stain under the tile of a hit by its colour
            if (DecalsOn)
            {
                string kind = CombatDecals.HitKind(e.Id, impact, value, e.Color);
                if (kind != null) Decals.Add(kind, e.Pos, now, Random());
            }
            // hit flash and shake
            if (Fx.HitFlash && target != 0)
            {
                var plan = Flasher.Plan(now, target, e.Id, impact, value, me != null && target == me.Id);
                if (plan != null)
                {
                    Flashes.Add(new FlashMark { Creature = target, Start = now, Ms = plan.Ms, Red = plan.Red });
                    while (Flashes.Count > 16) Flashes.RemoveAt(0);
                }
            }
            if (Fx.ScreenShake && e.Id == 24 && e.Typed) Shake.Start(now, ScreenShake.Amp(impact, e.Percent));
        }

        uint CreatureAt(Pos p)
        {
            var t = W.Get(p);
            if (t == null) return 0;
            foreach (var th in t.Things) if (th.IsCreature) return th.Creature.Id;
            return 0;
        }

        // ---------------------------------------------------------------------------------------------------- per frame
        /// <summary>Called every frame with the time (ms). Cheap; scans run at most every 250 or 500 ms.</summary>
        public void Tick(double now)
        {
            var w = W;
            var me = w.Player;
            if (me == null) { lastLevel = -1; return; }
            Wings.Tick(now);
            Decals.Step(now);
            Cosmetic.Tick(now);
            Hits.Prune(now);
            Grounds.RemoveAll(g => now - g.Born > GroundMs);
            Flashes.RemoveAll(f => now - f.Start > f.Ms + FlashHold);

            // level up sound (the own character only; the wings of others come as opcode 191)
            int lv = s.Parser.Level;
            if (lastLevel >= 0 && lv > lastLevel && !Wings.Own) Cue("levelup", 0);
            lastLevel = lv;
            // a goal done
            int goals = s.Progress.Goals.DoneCount;
            if (lastGoals >= 0 && goals > lastGoals) Cue("goal", 0);
            lastGoals = goals;
            // rare loot of a new kill
            var kills = LootKills();
            if (kills != null && kills.Count > 0)
            {
                int k = kills[0].K;
                if (lastKillK != int.MinValue && k != lastKillK) Cue(SoundLogic.LootEvent(kills[0].Items, LootAlerted(k)) ?? "", 0);
                lastKillK = k;
            }
            ScanCreatures(w, me, now);
            if (now - lastScan >= 500) { lastScan = now; ScanChests(w, me); }
            MusicTick(w, me, now);
        }

        void ScanCreatures(World w, Creature me, double now)
        {
            // creatures that left the view: a kill the player made, a blood stain, a footprint of each step
            foreach (var kv in w.Creatures)
            {
                var c = kv.Value;
                if (!seen.TryGetValue(c.Id, out var sc)) seen[c.Id] = sc = new SeenCreature();
                if (c.Type == 0 && lastPos.TryGetValue(c.Id, out var prev) && prev != c.Position) OnStep(c, prev, now, me);
                lastPos[c.Id] = c.Position;
                sc.Pos = c.Position; sc.Health = c.HealthPercent; sc.Type = c.Type; sc.Name = c.Name; sc.At = now;
            }
            List<uint> gone = null;
            foreach (var kv in seen) if (!w.Creatures.ContainsKey(kv.Key)) (gone ?? (gone = new List<uint>())).Add(kv.Key);
            if (gone == null) return;
            foreach (uint id in gone)
            {
                var sc = seen[id];
                seen.Remove(id); lastPos.Remove(id);
                bool died = sc.Type != 0 && sc.Type != 2 && sc.Health <= 30 && SoundLogic.Distance(me.Position, sc.Pos) <= 9;
                if (!died) continue;
                if (Hits.IsMyKill(id, now)) Cue("kill", SoundLogic.Distance(me.Position, sc.Pos));
                if (DecalsOn && CombatDecals.Bleeds(sc.Name)) Decals.Add("blood", sc.Pos, now, Random());
            }
        }

        void OnStep(Creature c, Pos from, double now, Creature me)
        {
            if (!Cosmetic.Looks.TryGetValue(c.Name, out var look) || look.Print == null) return;
            bool mine = c.Id == me.Id;
            if (!Cosmetic.Allowed(true, mine)) return;
            if (mine && (s.Parser.PlayerStates & MusicLogic.PzFlag) != 0) return;   // no new prints in a protection zone
            int rot = CosmeticFxState.StepRotation(from, c.Position);
            if (rot < 0) return;
            Cosmetic.AddPrint(c.Name, look.Print, from, rot, now);
        }

        void ScanChests(World w, Creature me)
        {
            Chests.Clear();
            if (!Aura.Enabled) return;
            foreach (var t in w.Tiles.Values)
            {
                if (t.Pos.Z != me.Position.Z || Math.Abs(t.Pos.X - me.Position.X) > 12 || Math.Abs(t.Pos.Y - me.Position.Y) > 10) continue;
                foreach (var th in t.Things)
                    if (!th.IsCreature && th.Item != null && ChestAuraState.Chests.TryGetValue(th.Item.Id, out var def)) Chests.Add(new ChestSpot { Pos = t.Pos, Def = def });
            }
        }

        // ---------------------------------------------------------------------------------------------------- music
        void MusicTick(World w, Creature me, double now)
        {
            if (now - lastMusic < MusicLogic.TickMs) return;
            lastMusic = now;
            var bosses = new List<KeyValuePair<Pos, int>>();
            foreach (var c in w.Creatures.Values)
                if (c.Type == 1 && s.Hud.Monster.Tier(c.Id) == "boss") bosses.Add(new KeyValuePair<Pos, int>(c.Position, c.HealthPercent));
            uint tgt = s.AttackTarget;
            bool tboss = false; int th = 0;
            if (tgt != 0 && w.Creatures.TryGetValue(tgt, out var tc) && s.Hud.Monster.Tier(tgt) == "boss") { tboss = true; th = tc.HealthPercent; }
            var snap = new MusicSnap
            {
                Online = true, Pos = me.Position, Pois = s.Utils.Marks.Pois, Activity = Activity(),
                ProtectionZone = (s.Parser.PlayerStates & MusicLogic.PzFlag) != 0,
                Boss = MusicLogic.BossEngaged(tboss, th, bosses, me.Position),
            };
            string region = MusicLogic.Step(MusicNow, MusicLogic.Wanted(snap), now, out bool changed);
            if (region != null) Region = region;
            if (changed) RegionChanged = true;
        }

        /// <summary>The flash of a creature now: 0 none, else 0..1 with the colour in red.</summary>
        public float FlashOf(uint creature, double now, out bool red)
        {
            red = false;
            for (int i = Flashes.Count - 1; i >= 0; i--)
            {
                var f = Flashes[i];
                if (f.Creature != creature) continue;
                float v = HitFlasher.Strength(now, f.Start, f.Ms);
                if (v > 0) { red = f.Red; return v; }
            }
            return 0f;
        }

        public void Clear()
        {
            Cues.Clear(); Grounds.Clear(); Flashes.Clear(); Chests.Clear(); Decals.Clear(); Wings.Clear(); Aura.Clear(); Cosmetic.Clear(); Names.Clear();
            Hits.Clear(); lastPos.Clear(); seen.Clear(); lastLevel = lastGoals = -1; lastKillK = int.MinValue;
        }
    }

    public sealed partial class GameSession
    {
        /// <summary>Sounds, music, auras, decals, wings, flashes and name shaders of this session (null before the constructor ran it).</summary>
        public VisualEffects Visual { get; private set; }

        /// <summary>Called by the constructor, after Ext, Hud and Progress exist.</summary>
        void InitVisual() { Visual = new VisualEffects(this); }

        /// <summary>Called by Poll.</summary>
        void VisualPoll() { Visual?.Tick(Now); }
    }
}
