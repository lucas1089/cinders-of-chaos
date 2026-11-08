// The live effects as items: Feed turns a server event (FxEvent) into missiles, bursts, floating numbers and slashes at times on the
// director's clock, Update drops what is over, Lights picks the few brightest light flashes. The rules:
//  - a magic effect is a burst in its element's colours (FrontFxArt.ImpactStrip); effects that are not combat (loot rays, teleports) draw nothing;
//    when many start at once (an area spell) the later ones are smaller and have no light;
//  - a distance shot is a missile flying at 16 tiles a second in a small arc; the effect and the numbers the server sends at the shot's end
//    wait for its landing (FrontFxTiming.LandingWindow), so the hit shows when the missile arrives;
//  - a damage number (0xB4 23, 24, 27) rises and fades above the target, in the colour of its element; a heal is green; the first and the
//    second value of one hit are two numbers; numbers on one tile stack;
//  - a physical hit next to an attacker (FrontFx.MeleeAttacker) with no missile at that tile also draws a slash from the attacker toward the target.
// Times are seconds on the clock Update was given. Pure C#, no Unity types: Unity/FrontLiveFx.cs draws the items.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class FxMissileItem
    {
        public int Id, Shot;                // Id: a running number; Shot: the server's missile id
        public Pos From, To;
        public FxElement El;
        public float T0, Dur, Tiles;
        public float U(float now) { return (now - T0) / Dur; }
    }

    public sealed class FxBurstItem
    {
        public int Id, EffectId;
        public Pos At;
        public FxElement El;
        public bool Heal, Light;
        public float T0, Scale = 1f;
        public float U(float now) { return (now - T0) / FrontFxTiming.BurstTime; }
    }

    public sealed class FxNumberItem
    {
        public int Id;
        public Pos At;
        public string Text;
        public FxElement El;
        public float T0, Size = 1f;
        public int Stack;                   // 0 for the first on a tile, then 1, 2, ... (each rises a step higher and swings to a side)
        /// <summary>Typed numbers (DamageScatter.cs): the creature the number follows (0: its tile), the scatter shift in pixels, the speed scale
        /// (the life is NumberLife / Speed) and the drift over the life in pixels (Sy up is negative; the stock rise is 48 pixels).</summary>
        public uint Creature;
        public int Dx, Dy, Sx, Sy;
        public float Speed = 1f;
        public bool Scattered;
        /// <summary>The impact type (ImpactType): a critical hit and a condition tick are drawn in the main client's bitmap fonts when the files are there (phase 7 track Y).</summary>
        public int Type;
        public float Life { get { return FrontFxTiming.NumberLife / (Speed > 0.05f ? Speed : 1f); } }
        public float U(float now) { return (now - T0) / Life; }
    }

    public sealed class FxSlashItem
    {
        public int Id;
        public Pos From, To;
        public uint AttackerId;   // the creature that swings (0: unknown)
        public FxElement El;
        public float T0;
        public float U(float now) { return (now - T0) / FrontFxTiming.SlashTime; }
    }

    /// <summary>A light the view may show: at tile At, or a missile's place between At and To (U), at a height in tiles, in a colour.</summary>
    public struct FxLight
    {
        public Pos At, To;
        public float U, Height, R, G, B, Intensity;
    }

    public sealed class FrontFxDirector
    {
        public const int MaxMissiles = 24, MaxBursts = 48, MaxNumbers = 32, MaxSlashes = 8;
        public const int CrowdBursts = 8;           // bursts started within CrowdWindow before the next one is small
        public const float CrowdWindow = 0.15f;
        public const float SlashGap = 0.25f;        // the same attacker slashes again no sooner than this

        public float Now;
        /// <summary>Typed damage numbers: the scatter of every number (on by default, level 2, as the main client).</summary>
        public readonly DamageScatter Scatter = new DamageScatter(1);
        public readonly List<FxMissileItem> Missiles = new List<FxMissileItem>();
        public readonly List<FxBurstItem> Bursts = new List<FxBurstItem>();
        public readonly List<FxNumberItem> Numbers = new List<FxNumberItem>();
        public readonly List<FxSlashItem> Slashes = new List<FxSlashItem>();
        int nextId = 1;
        readonly Dictionary<uint, float> lastSlash = new Dictionary<uint, float>();

        static void Cap<T>(List<T> l, int max) { while (l.Count >= max) l.RemoveAt(0); }

        static float Dist(Pos a, Pos b)
        {
            float dx = a.X - b.X, dy = a.Y - b.Y;
            return (float)Math.Sqrt(dx * dx + dy * dy);
        }

        /// <summary>Seconds until the missile that ends at p lands (0 when none is on its way there or it was launched long ago).</summary>
        public float LandingDelay(Pos p)
        {
            float delay = 0f;
            foreach (var m in Missiles)
                if (m.To == p && Now - m.T0 < FrontFxTiming.LandingWindow) delay = Math.Max(delay, m.T0 + m.Dur - Now);
            return delay;
        }

        bool MissileTo(Pos p)
        {
            foreach (var m in Missiles) if (m.To == p && Now - m.T0 < FrontFxTiming.LandingWindow + FrontFxTiming.MissileMax) return true;
            return false;
        }

        public void Feed(World w, FxEvent e)
        {
            switch (e.Kind)
            {
                case FxKind.Effect: AddEffect(e); break;
                case FxKind.Missile: AddMissile(e); break;
                case FxKind.Number: AddNumber(w, e); break;
                case FxKind.AnimText: AddText(e); break;
            }
        }

        void AddEffect(FxEvent e)
        {
            var el = FrontFx.ElementOfEffect(e.Id);
            if (el == FxElement.None) return;
            float t0 = Now + LandingDelay(e.Pos);
            int crowd = 0;
            foreach (var b in Bursts) if (Math.Abs(b.T0 - t0) < CrowdWindow) crowd++;
            Cap(Bursts, MaxBursts);
            Bursts.Add(new FxBurstItem { Id = nextId++, EffectId = e.Id, At = e.Pos, El = el, Heal = el == FxElement.Heal, T0 = t0, Light = crowd < CrowdBursts, Scale = crowd < CrowdBursts ? 1f : 0.7f });
        }

        void AddMissile(FxEvent e)
        {
            float tiles = Dist(e.Pos, e.To);
            Cap(Missiles, MaxMissiles);
            Missiles.Add(new FxMissileItem { Id = nextId++, Shot = e.Id, From = e.Pos, To = e.To, El = FrontFx.ElementOfMissile(e.Id), T0 = Now, Tiles = tiles, Dur = FrontFxTiming.Flight(tiles) });
        }

        FxNumberItem MakeNumber(Pos at, string text, FxElement el, float t0, float size, int type = 0, bool experience = false, uint creature = 0)
        {
            int stack = 0;
            foreach (var n in Numbers) if (n.At == at && Math.Abs(n.T0 - t0) < 0.5f) stack++;
            Cap(Numbers, MaxNumbers);
            var item = new FxNumberItem { Id = nextId++, At = at, Text = text, El = el, T0 = t0, Size = size, Stack = stack, Creature = creature, Type = type };
            ScatterRoll roll;
            if (Scatter.Pick(at, Now * 1000.0, type, experience, out roll))
            {
                item.Dx = roll.Dx; item.Dy = roll.Dy; item.Sx = roll.Sx; item.Sy = roll.Sy; item.Speed = roll.Speed; item.Scattered = true;
            }
            Numbers.Add(item);
            return item;
        }

        void AddNumber(World w, FxEvent e)
        {
            int type = e.Id;
            float t0 = Now + LandingDelay(e.Pos);
            float size = type == 24 ? 1.25f : (type == 27 || type == 28 || type == 29 ? 0.8f : 1f);
            int impact = e.Typed ? e.Impact : ImpactType.Normal;
            if (impact == ImpactType.Critical) size *= ImpactType.CritSize;
            else if (impact == ImpactType.Condition) size *= ImpactType.ConditionSize;
            if (type == 23 || type == 24 || type == 27)
            {
                bool physical = false;
                if (e.Value > 0) { var el = TypedElement(e, e.Color); physical |= FrontFx.IsPhysical(el); MakeNumber(e.Pos, FrontFx.Format(e.Value), el, t0, size, impact, false, e.Creature); }
                if (e.Value2 > 0) { var el = TypedElement(e, e.Color2); physical |= FrontFx.IsPhysical(el); MakeNumber(e.Pos, FrontFx.Format(e.Value2), el, t0, size, impact, false, e.Creature); }
                if (physical && !MissileTo(e.Pos)) AddSlash(w, e);
            }
            else if (type == 25 || type == 28)
            {
                if (e.Value > 0) MakeNumber(e.Pos, (e.Typed && impact == ImpactType.ManaGain ? "+" : "") + FrontFx.Format(e.Value), e.Typed && impact == ImpactType.ManaGain ? FxElement.Water : FxElement.Heal, t0, size, impact, false, e.Creature);
            }
            else if (type == 26 || type == 29)
            {
                if (e.Value > 0) MakeNumber(e.Pos, "+" + FrontFx.Format(e.Value), FxElement.Holy, t0, size * 0.8f, impact, true, e.Creature);
            }
        }

        /// <summary>The element of a damage number: the text colour says it, except the types that name their own look (mana drain: water, energy shield: energy).</summary>
        static FxElement TypedElement(FxEvent e, byte color)
        {
            if (e.Typed)
            {
                if (e.Impact == ImpactType.ManaDrain) return FxElement.Water;
                if (e.Impact == ImpactType.EnergyShield) return FxElement.Energy;
            }
            return FrontFx.ElementOfTextColor(color);
        }

        void AddSlash(World w, FxEvent e)
        {
            var who = FrontFx.MeleeAttacker(w, e.Pos, e.Id, e.Text);
            if (who == null) return;
            float last;
            if (lastSlash.TryGetValue(who.Id, out last) && Now - last < SlashGap) return;
            lastSlash[who.Id] = Now;
            Cap(Slashes, MaxSlashes);
            Slashes.Add(new FxSlashItem { Id = nextId++, AttackerId = who.Id, From = who.Position, To = e.Pos, El = FrontFx.ElementOfTextColor(e.Color), T0 = Now });
        }

        void AddText(FxEvent e)
        {
            if (string.IsNullOrEmpty(e.Text)) return;
            var el = FrontFx.ElementOfTextColor(e.Color);
            MakeNumber(e.Pos, e.Text.Length > 12 ? e.Text.Substring(0, 12) : e.Text, el, Now + LandingDelay(e.Pos), 0.9f);
        }

        /// <summary>Moves the clock and drops the items that are over.</summary>
        public void Update(float now)
        {
            Now = now;
            Missiles.RemoveAll(m => now > m.T0 + m.Dur);
            Bursts.RemoveAll(b => now > b.T0 + FrontFxTiming.BurstTime);
            Numbers.RemoveAll(n => now > n.T0 + n.Life);
            Slashes.RemoveAll(s => now > s.T0 + FrontFxTiming.SlashTime);
            if (lastSlash.Count > 64) lastSlash.Clear();
        }

        public void Clear()
        {
            Missiles.Clear(); Bursts.Clear(); Numbers.Clear(); Slashes.Clear(); lastSlash.Clear();
        }

        static FxLight Make(Pos a, Pos b, float u, float height, FxElement el, float intensity)
        {
            var p = FrontFx.Palette(el);
            return new FxLight { At = a, To = b, U = u, Height = height, R = p.BR, G = p.BG, B = p.BB, Intensity = intensity };
        }

        /// <summary>The brightest light flashes now, at most max: a missile in flight (0.8), a burst's flash (3, over FlashTime), a slash's (2.5).</summary>
        public void Lights(List<FxLight> into, int max)
        {
            into.Clear();
            foreach (var m in Missiles)
            {
                float u = m.U(Now);
                if (u >= 0f && u <= 1f) into.Add(Make(m.From, m.To, u, 0.5f + FrontFxTiming.Arc(m.Tiles, u), m.El, 0.8f));
            }
            foreach (var b in Bursts)
            {
                float age = Now - b.T0;
                if (b.Light && age >= 0f && age < FrontFxTiming.FlashTime) into.Add(Make(b.At, b.At, 0f, 0.5f, b.El, 3f * FrontFxTiming.Flash(age / FrontFxTiming.FlashTime) * b.Scale));
            }
            foreach (var s in Slashes)
            {
                float age = Now - s.T0;
                if (age >= 0f && age < FrontFxTiming.FlashTime) into.Add(Make(s.To, s.To, 0f, 0.5f, s.El, 2.5f * FrontFxTiming.Flash(age / FrontFxTiming.FlashTime)));
            }
            if (into.Count > max)
            {
                into.Sort((a, b) => b.Intensity.CompareTo(a.Intensity));
                into.RemoveRange(max, into.Count - max);
            }
        }
    }
}
