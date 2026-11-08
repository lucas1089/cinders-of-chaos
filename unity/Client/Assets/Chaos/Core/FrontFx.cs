// Live combat effects in the front-art look, the engine-free part: what the parser read (FxEvent, the FxFeed queue on World), which
// element every server effect id, missile id and damage colour is (FrontFxIds.cs, generated), the palette and the missile art kind of
// each element, number text, the melee rule (who swings when a physical hit lands next to an attacker) and the timing of missiles,
// bursts, floating numbers, slashes and light flashes. FrontFxDirector.cs turns events into live items, FrontFxArt.cs draws the
// pictures, Unity/FrontLiveFx.cs shows them. Pure C#, no Unity types.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>The look of a hit or a spell. Poison and Earth have no missile art of their own (a tinted one is used).</summary>
    public enum FxElement { Neutral, Fire, Ice, Energy, Arcane, Death, Holy, Physical, Blood, Shadow, Poison, Earth, Water, Heal, None }

    public enum FxKind { Effect, Missile, Number, AnimText, Square }

    /// <summary>One thing the server said about combat: a magic effect (0x83), a distance shot (0x85), animated text (0x84), a creature square
    /// (0x86) or a damage / heal / experience message (0xB4 modes 23..29).</summary>
    public struct FxEvent
    {
        public FxKind Kind;
        public Pos Pos, To;          // Effect, Number and AnimText: Pos. Missile: Pos is the start, To the end
        public int Id;               // effect or missile id; a Number's message type (23 dealt, 24 received, 25 healed, 26 experience, 27 damage of others, 28 heal of others, 29 experience of others)
        public uint Value, Value2;   // Number: the first and the second damage value
        public byte Color, Color2;   // text colours (TFS TextColor_t) of the two values; Square: the colour
        public uint Creature;        // Square: the creature id. Number: the creature the number belongs to (typed numbers, 0: its tile)
        public bool Typed;           // Number: read with capability bit 7, so Percent, Impact and Creature are set
        public int Percent;          // Number (typed): the value as a share of the target's maximum, x100 (10000 = 100 percent)
        public int Impact;           // Number (typed): ImpactType (0 normal, 1 critical, 2 condition tick, 3 mana drain, 4 mana gain, 5 energy shield)
        public string Text;           // Number: the sentence ("A rat loses 5 hitpoints due to your attack."); AnimText: the text

        public static FxEvent Effect(Pos p, int id) { return new FxEvent { Kind = FxKind.Effect, Pos = p, Id = id }; }
        public static FxEvent Missile(Pos a, Pos b, int id) { return new FxEvent { Kind = FxKind.Missile, Pos = a, To = b, Id = id }; }
        public static FxEvent AnimText(Pos p, byte color, string text) { return new FxEvent { Kind = FxKind.AnimText, Pos = p, Color = color, Text = text ?? "" }; }
        public static FxEvent Square(uint creature, byte color) { return new FxEvent { Kind = FxKind.Square, Creature = creature, Color = color }; }
        public static FxEvent Number(int type, Pos p, uint v1, byte c1, uint v2, byte c2, string text)
        {
            return new FxEvent { Kind = FxKind.Number, Id = type, Pos = p, Value = v1, Color = c1, Value2 = v2, Color2 = c2, Text = text ?? "" };
        }
        /// <summary>A number of a typed message (capability bit 7): the percent, the impact type and the creature it belongs to.</summary>
        public static FxEvent TypedNumber(int type, Pos p, uint v1, byte c1, uint v2, byte c2, string text, int percent, int impact, uint creature)
        {
            var e = Number(type, p, v1, c1, v2, c2, text);
            e.Typed = true; e.Percent = percent; e.Impact = impact; e.Creature = creature;
            return e;
        }
    }

    /// <summary>The events the parser read, waiting for the live view. Off (nothing queued) until a consumer sets Enabled; capped, the oldest go first.</summary>
    public sealed class FxFeed
    {
        public const int Max = 512;
        bool enabledFlag;
        /// <summary>A second reader (Core/GameVisual.cs: sounds, decals, flashes) that sees every event whether or not the live view drains the queue.</summary>
        public Action<FxEvent> Tap;
        /// <summary>True while the live view wants the events or a tap listens (the parser pushes only then).</summary>
        public bool Enabled { get { return enabledFlag || Tap != null; } set { enabledFlag = value; } }
        readonly Queue<FxEvent> q = new Queue<FxEvent>();
        public int Count { get { return q.Count; } }
        public void Push(FxEvent e) { if (Tap != null) Tap(e); if (!enabledFlag) return; if (q.Count >= Max) q.Dequeue(); q.Enqueue(e); }
        public bool TryDequeue(out FxEvent e)
        {
            if (q.Count == 0) { e = default(FxEvent); return false; }
            e = q.Dequeue();
            return true;
        }
        public void Clear() { q.Clear(); }
    }

    /// <summary>Three colours of an element (0..1): the hot core, the body, the dark rim. The same idea as palette() of tools/front_art_packs.py.</summary>
    public struct FxPalette
    {
        public float CR, CG, CB, BR, BG, BB, RR, RG, RB;
    }

    /// <summary>The missile art to use for an element: the folder fx_&lt;Kind&gt; of the projectile sheets, and a tint (1,1,1 = none).</summary>
    public struct FxMissileLook { public string Kind; public float R, G, B; }

    public static class FrontFx
    {
        // ---- ids -> elements ----

        static Dictionary<int, FxElement> effects, missiles;

        static FxElement Letter(char c)
        {
            switch (c)
            {
                case 'F': return FxElement.Fire;
                case 'I': return FxElement.Ice;
                case 'E': return FxElement.Energy;
                case 'A': return FxElement.Arcane;
                case 'D': return FxElement.Death;
                case 'H': return FxElement.Holy;
                case 'P': return FxElement.Physical;
                case 'B': return FxElement.Blood;
                case 'S': return FxElement.Shadow;
                case 'V': return FxElement.Poison;
                case 'T': return FxElement.Earth;
                case 'W': return FxElement.Water;
                case 'L': return FxElement.Heal;
                case 'X': return FxElement.None;
                default: return FxElement.Neutral;
            }
        }

        /// <summary>Decodes the runs of FrontFxIds ("372-378F,379I").</summary>
        public static Dictionary<int, FxElement> Decode(string runs)
        {
            var d = new Dictionary<int, FxElement>();
            foreach (var run in runs.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries))
            {
                char letter = run[run.Length - 1];
                string span = run.Substring(0, run.Length - 1);
                int dash = span.IndexOf('-');
                int a = int.Parse(dash < 0 ? span : span.Substring(0, dash));
                int b = dash < 0 ? a : int.Parse(span.Substring(dash + 1));
                for (int i = a; i <= b; i++) d[i] = Letter(letter);
            }
            return d;
        }

        public static IDictionary<int, FxElement> EffectTable { get { if (effects == null) effects = Decode(FrontFxIds.Effects); return effects; } }
        public static IDictionary<int, FxElement> MissileTable { get { if (missiles == null) missiles = Decode(FrontFxIds.Missiles); return missiles; } }

        /// <summary>The element of a magic effect id; None for pictures that are not combat (loot rays, teleports, puffs); Neutral for an id the table does not know.</summary>
        public static FxElement ElementOfEffect(int id)
        {
            FxElement e;
            return EffectTable.TryGetValue(id, out e) ? e : FxElement.Neutral;
        }

        public static FxElement ElementOfMissile(int id)
        {
            FxElement e;
            return MissileTable.TryGetValue(id, out e) ? (e == FxElement.None || e == FxElement.Heal ? FxElement.Neutral : e) : FxElement.Neutral;
        }

        /// <summary>The element of a damage text colour (TFS TextColor_t as combat.cpp / game.cpp pick them for each combat type).</summary>
        public static FxElement ElementOfTextColor(int color)
        {
            switch (color)
            {
                case 180: case 194: return FxElement.Physical;   // red: physical, life drain (194 pastel red)
                case 198: return FxElement.Fire;                 // orange
                case 154: case 155: return FxElement.Energy;     // purple, electric purple
                case 30: return FxElement.Earth;                 // light green
                case 35: case 5: case 95: return FxElement.Water; // light blue
                case 143: return FxElement.Ice;                  // teal
                case 210: return FxElement.Holy;                 // yellow
                case 108: return FxElement.Death;                // dark red
                default: return FxElement.Neutral;
            }
        }

        // ---- look of an element ----

        static FxPalette P(int cr, int cg, int cb, int br, int bg, int bb, int rr, int rg, int rb)
        {
            return new FxPalette { CR = cr / 255f, CG = cg / 255f, CB = cb / 255f, BR = br / 255f, BG = bg / 255f, BB = bb / 255f, RR = rr / 255f, RG = rg / 255f, RB = rb / 255f };
        }

        public static FxPalette Palette(FxElement e)
        {
            switch (e)
            {
                case FxElement.Fire: return P(255, 236, 160, 255, 150, 40, 190, 60, 20);
                case FxElement.Ice: return P(230, 250, 255, 120, 200, 255, 50, 110, 200);
                case FxElement.Energy: return P(230, 255, 255, 120, 210, 255, 150, 100, 255);
                case FxElement.Arcane: return P(255, 220, 255, 220, 110, 255, 120, 50, 190);
                case FxElement.Death: return P(235, 255, 225, 130, 210, 140, 50, 100, 80);
                case FxElement.Holy: return P(255, 255, 225, 255, 225, 120, 210, 150, 50);
                case FxElement.Physical: return P(255, 255, 255, 220, 220, 230, 140, 140, 160);
                case FxElement.Blood: return P(255, 200, 190, 220, 40, 40, 110, 10, 20);
                case FxElement.Shadow: return P(210, 170, 255, 110, 60, 170, 50, 20, 90);
                case FxElement.Poison: return P(200, 255, 120, 90, 210, 50, 30, 110, 30);
                case FxElement.Earth: return P(235, 225, 160, 150, 170, 70, 90, 80, 40);
                case FxElement.Water: return P(220, 255, 255, 80, 170, 230, 30, 90, 170);
                case FxElement.Heal: return P(230, 255, 230, 90, 230, 120, 40, 150, 80);
                default: return P(255, 255, 255, 210, 220, 235, 130, 140, 160);
            }
        }

        /// <summary>The missile pictures the projectile sheets have: fireball, frost, arcane, skull_necrotic, skull_spirit, blood, shadow, holy.</summary>
        public static readonly string[] MissileKinds = { "fireball", "frost", "arcane", "skull_necrotic", "skull_spirit", "blood", "shadow", "holy" };

        /// <summary>Element to missile art (see MissileKinds): fire is the fireball, ice the frost shard, energy and arcane the arcane missile (energy
        /// tinted cyan), death the necrotic skull, holy the holy orb, physical and blood the blood bolt, shadow the shadow bolt. Poison and earth use the
        /// spirit skull tinted green, water the frost shard tinted teal.</summary>
        public static FxMissileLook MissileLook(FxElement e)
        {
            switch (e)
            {
                case FxElement.Fire: return Look("fireball", 1f, 1f, 1f);
                case FxElement.Ice: return Look("frost", 1f, 1f, 1f);
                case FxElement.Energy: return Look("frost", 0.9f, 1.05f, 1.45f);
                case FxElement.Arcane: return Look("arcane", 1f, 1f, 1f);
                case FxElement.Death: return Look("skull_necrotic", 1f, 1f, 1f);
                case FxElement.Holy: case FxElement.Heal: return Look("holy", 1f, 1f, 1f);
                case FxElement.Physical: case FxElement.Blood: return Look("blood", 1f, 1f, 1f);
                case FxElement.Shadow: return Look("shadow", 1f, 1f, 1f);
                case FxElement.Poison: return Look("skull_spirit", 0.75f, 1.4f, 0.55f);
                case FxElement.Earth: return Look("skull_spirit", 1.15f, 1.2f, 0.6f);
                case FxElement.Water: return Look("frost", 0.7f, 1.1f, 1.15f);
                default: return Look("arcane", 1f, 1f, 1f);
            }
        }

        static FxMissileLook Look(string kind, float r, float g, float b) { return new FxMissileLook { Kind = kind, R = r, G = g, B = b }; }

        // ---- text ----

        /// <summary>A number for the pixel font: whole up to 9999, then 12.3K, 123K, 12.3M, 1.2B (the font has K, M and B).</summary>
        public static string Format(long v)
        {
            if (v < 0) v = -v;
            if (v < 10000) return v.ToString();
            if (v < 1000000) return Scaled(v, 1000, "K");
            if (v < 1000000000) return Scaled(v, 1000000, "M");
            return Scaled(v, 1000000000, "B");
        }

        static string Scaled(long v, long unit, string suffix)
        {
            long whole = v / unit;
            if (whole >= 100) return whole + suffix;
            long tenth = (v % unit) * 10 / unit;
            return tenth == 0 ? whole + suffix : whole + "." + tenth + suffix;
        }

        // ---- melee ----

        public static Creature CreatureAt(World w, Pos p)
        {
            var t = w.Get(p);
            if (t == null) return null;
            foreach (var th in t.Things) if (th.IsCreature) return th.Creature;
            return null;
        }

        static string Plain(string name)
        {
            name = (name ?? "").Trim().TrimEnd('.').ToLowerInvariant();
            foreach (var art in new[] { "a ", "an ", "the " }) if (name.StartsWith(art)) return name.Substring(art.Length);
            return name;
        }

        /// <summary>The attacker named by a damage sentence ("... due to an attack by a rat." gives "rat"); null when it names none or "your attack".</summary>
        public static string AttackerName(string text)
        {
            if (string.IsNullOrEmpty(text)) return null;
            int at = text.LastIndexOf(" by ", StringComparison.Ordinal);
            if (at < 0) return null;
            string n = Plain(text.Substring(at + 4));
            return n.Length == 0 ? null : n;
        }

        /// <summary>True when the creature looks at the tile (its direction is the sign of the step to it).</summary>
        public static bool Faces(Creature c, Pos target)
        {
            int dx = Math.Sign(target.X - c.Position.X), dy = Math.Sign(target.Y - c.Position.Y);
            switch (c.Direction)
            {
                case Dir.North: return dy < 0;
                case Dir.South: return dy > 0;
                case Dir.East: return dx > 0;
                case Dir.West: return dx < 0;
                case Dir.NorthEast: return dx > 0 && dy < 0;
                case Dir.SouthEast: return dx > 0 && dy > 0;
                case Dir.SouthWest: return dx < 0 && dy > 0;
                default: return dx < 0 && dy < 0;
            }
        }

        static bool Hostile(Creature attacker, Creature target)
        {
            bool aMon = attacker.Type == 1, tMon = target.Type == 1;
            if (aMon && !tMon) return target.Type != 2;      // a monster hits players and summons, not npcs
            if (!aMon && tMon) return attacker.Type != 2;    // players and summons hit monsters
            return false;
        }

        /// <summary>Who swings when a damage message lands: a creature on a tile next to the target. Rule, in order: the sentence names the attacker
        /// ("by a rat") and one next to the target has that name; our own hit ("your attack", type 23) is ours when we stand next to the target; otherwise
        /// the creatures next to the target that are hostile to it, the one that faces it first, then the nearest in the order of the world's creature list.
        /// Null when there is none (a ranged hit or a spell).</summary>
        public static Creature MeleeAttacker(World w, Pos target, int msgType, string text)
        {
            var tc = CreatureAt(w, target);
            var near = new List<Creature>();
            for (int dy = -1; dy <= 1; dy++)
                for (int dx = -1; dx <= 1; dx++)
                {
                    if (dx == 0 && dy == 0) continue;
                    var c = CreatureAt(w, target.Offset(dx, dy));
                    if (c != null && c != tc) near.Add(c);
                }
            if (near.Count == 0) return null;
            string named = AttackerName(text);
            if (named != null) foreach (var c in near) if (Plain(c.Name) == named) return c;
            var me = w.Player;
            if (msgType == 23) return me != null && near.Contains(me) ? me : null;
            Creature best = null;
            int bestScore = -1;
            foreach (var c in near)
            {
                if (tc != null && !Hostile(c, tc)) continue;
                int score = Faces(c, target) ? 2 : 1;
                if (score > bestScore) { best = c; bestScore = score; }
            }
            return best;
        }

        /// <summary>A physical hit draws a slash; other elements are spells or bites that have their own effect.</summary>
        public static bool IsPhysical(FxElement e) { return e == FxElement.Physical || e == FxElement.Blood; }
    }

    /// <summary>The timing of the live effects, all in seconds and tiles.</summary>
    public static class FrontFxTiming
    {
        public const float MissileSpeed = 16f;      // tiles a second
        public const float MissileMin = 0.12f, MissileMax = 0.7f;
        public const float ArcPerTile = 0.06f, ArcMax = 0.5f;   // the missile's rise at mid flight, in tiles
        public const float BurstTime = 0.5f;
        public const int BurstFrames = 12;
        public const float NumberLife = 1.1f, NumberRise = 1.2f, NumberHeight = 0.9f;   // rise and start height in tiles
        public const float SlashTime = 0.3f;
        public const float FlashTime = 0.3f;
        public const float LandingWindow = 0.35f;   // an effect or number at a missile's end within this long of its launch waits for the landing

        public static float Flight(float tiles)
        {
            return Math.Min(MissileMax, Math.Max(MissileMin, tiles / MissileSpeed));
        }

        public static float Arc(float tiles, float u)
        {
            return Math.Min(ArcMax, ArcPerTile * tiles) * 4f * u * (1f - u);
        }

        public static float Clamp01(float u) { return u < 0f ? 0f : (u > 1f ? 1f : u); }

        public static int BurstFrame(float u)
        {
            return Math.Min(BurstFrames - 1, Math.Max(0, (int)(Clamp01(u) * BurstFrames)));
        }

        public static int SlashFrame(float u)
        {
            return Math.Min(FrontArtSlash.Frames - 1, Math.Max(0, (int)(Clamp01(u) * FrontArtSlash.Frames)));
        }

        /// <summary>How far a floating number has risen (tiles) at progress u: fast at first, then slow.</summary>
        public static float NumberRiseAt(float u)
        {
            u = Clamp01(u);
            return NumberRise * (1f - (1f - u) * (1f - u));
        }

        /// <summary>Opacity of a number: full for 60 percent of its life, then a fade.</summary>
        public static float NumberAlpha(float u)
        {
            u = Clamp01(u);
            return u < 0.6f ? 1f : Math.Max(0f, 1f - (u - 0.6f) / 0.4f);
        }

        /// <summary>A pop: 1.5 times its size at the start, settled after 12 percent of its life.</summary>
        public static float NumberScale(float u)
        {
            u = Clamp01(u);
            return u < 0.12f ? 1.5f - 0.5f * (u / 0.12f) : 1f;
        }

        /// <summary>A light flash's strength: 1 at the start, down to 0 squared.</summary>
        public static float Flash(float u)
        {
            u = Clamp01(u);
            return (1f - u) * (1f - u);
        }
    }
}
