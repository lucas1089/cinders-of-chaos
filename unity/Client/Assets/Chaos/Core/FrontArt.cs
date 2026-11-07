// Front-art scene (test of a new look): the blocky diorama and its characters, as plain data.
// A tile grid with height levels of 0.5 units (courtyard, ragged temple wall with a gate, steps, a low wall ring, pillars,
// gravestones, a sarcophagus, braziers), boxes for the props, point lights, and four front-facing characters. The mesher
// turns the grid and the boxes into quads per texture kind (hidden faces dropped, vertex ambient occlusion), so a player merges
// one mesh per material. Which of the 8 character pictures to show for a facing and a camera yaw is FrontArtFacing.
// Pure C#, no Unity types: Unity/FrontArtScene.cs draws it, Core.Tests checks it.
// World axes: +x east, +z north (away from the camera), +y up. Tile (x, z) covers x..x+1, z..z+1.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>An axis-aligned box turned about Y around its centre. Tint multiplies the texture (1 = as drawn).</summary>
    public struct FaBox
    {
        public float X0, Y0, Z0, X1, Y1, Z1, Yaw;   // yaw in degrees
        public FaTex Tex;
        public float R, G, B;
        public int Seed;
        public string Tag;
    }

    public struct FaLight
    {
        public float X, Y, Z, R, G, B, Range, Intensity;
        public float FlameX, FlameY, FlameZ, FlameSize;   // where a flame burns and how big (1 = a brazier), for the lights that have one
        public bool Flame;
        public int Seed;
    }

    public struct FaActor
    {
        public string Name, Folder;   // Folder: knight, mage, skeleton, ghoul, pk_<name> (Resources/FrontArt/<Folder>/<direction>.png)
        public float X, Y, Z, FaceX, FaceZ;
        public float Units;           // the picture's side in units; 0: the scene's default (48 texels, 1.5 units)
        public bool Monster;
        public bool Walks;            // pack monsters: walks to (WalkX, WalkZ) and back (FrontArtWalk)
        public float WalkX, WalkZ;
    }

    /// <summary>Where a patrolling figure is at time t: it stands at its spot (X, Z) facing (FaceX, FaceZ), walks to (WalkX, WalkZ),
    /// stands there looking back, walks home. Phase shifts each figure's start so they do not move in step.</summary>
    public static class FrontArtWalk
    {
        public const float Speed = 0.75f;   // units a second
        public const float Pause = 1.4f;    // seconds standing at each end

        public struct Pose { public float X, Z, FaceX, FaceZ; public bool Walking; }

        /// <summary>The start shift of the i-th extra.</summary>
        public static float Phase(int i) { return i * 1.37f; }

        public static float Cycle(FaActor a)
        {
            return 2f * (Length(a) / Speed + Pause);
        }

        public static float Length(FaActor a)
        {
            float dx = a.WalkX - a.X, dz = a.WalkZ - a.Z;
            return (float)Math.Sqrt(dx * dx + dz * dz);
        }

        public static Pose At(FaActor a, float t, float phase)
        {
            var p = new Pose { X = a.X, Z = a.Z, FaceX = a.FaceX, FaceZ = a.FaceZ };
            float len = Length(a);
            if (!a.Walks || len < 1e-4f) return p;
            float dx = (a.WalkX - a.X) / len, dz = (a.WalkZ - a.Z) / len, go = len / Speed, cycle = 2f * (go + Pause);
            float u = (float)((((t + phase) % cycle) + cycle) % cycle);
            if (u < Pause) return p;                                   // at home, facing the scene
            u -= Pause;
            if (u < go) { float d = u * Speed; return new Pose { X = a.X + dx * d, Z = a.Z + dz * d, FaceX = dx, FaceZ = dz, Walking = true }; }
            u -= go;
            if (u < Pause) return new Pose { X = a.WalkX, Z = a.WalkZ, FaceX = -dx, FaceZ = -dz };   // at the far end, looking back
            u -= Pause;
            float back = len - u * Speed;
            return new Pose { X = a.X + dx * back, Z = a.Z + dz * back, FaceX = -dx, FaceZ = -dz, Walking = true };
        }
    }

    /// <summary>An attack spell: the caster plays its attack, a missile flies to the target (following it), an impact plays there.
    /// Art: Resources/FrontArt/fx_&lt;Missile&gt;/missile.png and fx_&lt;Impact&gt;/impact.png (unity/tools/front_art_packs.py fx).</summary>
    public struct FaSpell
    {
        public string Caster, Target;   // names of extras or actors
        public string Missile, Impact;
        public float R, G, B;           // the missile's light
        public float Offset;            // seconds into the caster's cycle the cast starts (a walker: inside its stand at home)
        public float Period;            // a caster that does not walk: seconds between casts
    }

    /// <summary>The state of a spell at a time: casting, the missile in flight, the impact.</summary>
    public static class FrontArtSpells
    {
        public const float CastTime = 0.75f;   // the attack animation (9 frames at 12)
        public const float Release = 0.45f;    // the missile leaves this far into the cast
        public const float Speed = 5.5f;       // units a second
        public const float ImpactTime = 1.0f;  // the impact animation
        public const float Arc = 0.45f;        // the missile's rise at mid flight
        public const float Chest = 0.42f;      // launch and hit height, times the picture's side

        public struct State
        {
            public bool Casting, Flying, Hit;
            public float CastU, HitU;          // 0..1 through the cast and the impact
            public float X, Y, Z;              // the missile, or the impact's centre
            public float DirX, DirY, DirZ;     // the missile's heading
            public float FaceX, FaceZ;         // the caster turns to the target while casting
        }

        static bool Find(FrontArtLayout L, string name, out FaActor a, out float phase)
        {
            for (int i = 0; i < L.Extras.Count; i++) if (L.Extras[i].Name == name) { a = L.Extras[i]; phase = FrontArtWalk.Phase(i); return true; }
            for (int i = 0; i < L.Actors.Count; i++) if (L.Actors[i].Name == name) { a = L.Actors[i]; phase = 0f; return true; }
            a = default(FaActor); phase = 0f;
            return false;
        }

        static float Size(FaActor a) { return a.Units > 0f ? a.Units : 1.5f; }

        /// <summary>Where a figure is at time t (walkers follow FrontArtWalk), at chest height.</summary>
        public static void Chest3(FrontArtLayout L, FaActor a, float phase, float t, out float x, out float y, out float z)
        {
            var p = FrontArtWalk.At(a, t, phase);
            x = p.X; z = p.Z;
            y = L.GroundY(x, z) + Chest * Size(a);
        }

        /// <summary>The seconds between two casts of this spell.</summary>
        public static float Cycle(FrontArtLayout L, FaSpell s)
        {
            FaActor c; float ph;
            if (!Find(L, s.Caster, out c, out ph)) return 1f;
            return c.Walks ? FrontArtWalk.Cycle(c) : s.Period;
        }

        /// <summary>Seconds from release to hit for the cast that started at t0.</summary>
        public static float Flight(FrontArtLayout L, FaSpell s, float t0)
        {
            FaActor c, g; float pc, pg;
            if (!Find(L, s.Caster, out c, out pc) || !Find(L, s.Target, out g, out pg)) return 0f;
            float ax, ay, az, bx, by, bz;
            Chest3(L, c, pc, t0 + Release, out ax, out ay, out az);
            Chest3(L, g, pg, t0 + Release, out bx, out by, out bz);
            float d = (float)Math.Sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay) + (bz - az) * (bz - az));
            return d / Speed;
        }

        public static State At(FrontArtLayout L, FaSpell s, float t)
        {
            var st = new State();
            FaActor c, g; float pc, pg;
            if (!Find(L, s.Caster, out c, out pc) || !Find(L, s.Target, out g, out pg)) return st;
            float cycle = Cycle(L, s);
            float k = (float)Math.Floor((t + pc - s.Offset) / cycle);
            float t0 = k * cycle + s.Offset - pc;   // this cast's start
            float local = t - t0;
            float ax, ay, az, bx, by, bz;
            Chest3(L, c, pc, t0 + Release, out ax, out ay, out az);
            Chest3(L, g, pg, t0 + Release, out bx, out by, out bz);
            st.FaceX = bx - ax; st.FaceZ = bz - az;
            if (local < CastTime) { st.Casting = true; st.CastU = local / CastTime; }
            float fly = Flight(L, s, t0);
            if (local >= Release && local < Release + fly)
            {
                float f = (local - Release) / fly;
                float tx, ty, tz;
                Chest3(L, g, pg, t, out tx, out ty, out tz);   // the missile follows the target
                float lift = Arc * 4f * f * (1f - f);
                st.Flying = true;
                st.X = ax + (tx - ax) * f; st.Y = ay + (ty - ay) * f + lift; st.Z = az + (tz - az) * f;
                st.DirX = tx - ax; st.DirY = ty - ay + Arc * 4f * (1f - 2f * f); st.DirZ = tz - az;
            }
            else if (local >= Release + fly && local < Release + fly + ImpactTime)
            {
                st.Hit = true;
                st.HitU = (local - Release - fly) / ImpactTime;
                Chest3(L, g, pg, t0 + Release + fly, out st.X, out st.Y, out st.Z);
            }
            return st;
        }
    }

    /// <summary>Which of the 8 direction pictures shows a character: the facing against the camera's yaw.</summary>
    public static class FrontArtFacing
    {
        /// <summary>The names of the pictures, clockwise from north (the picture "south" looks at the viewer).</summary>
        public static readonly string[] Dirs = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" };

        /// <summary>Index into Dirs. (fx, fz) is the world facing, camYawDeg the camera's heading (0 looks north, +90 looks east).</summary>
        public static int Index(float fx, float fz, float camYawDeg)
        {
            if (Math.Abs(fx) < 1e-5f && Math.Abs(fz) < 1e-5f) return 4;
            double a = Math.Atan2(fx, fz) * 180.0 / Math.PI - camYawDeg;
            a = ((a % 360.0) + 360.0) % 360.0;
            return ((int)Math.Round(a / 45.0)) % 8;
        }

        public static string Name(float fx, float fz, float camYawDeg) { return Dirs[Index(fx, fz, camYawDeg)]; }
    }

    /// <summary>The diorama camera: a narrow field of view from far away, tilted down, looking at a target point.</summary>
    public static class FrontArtCamera
    {
        public const float Fov = 28f, Pitch = 33f;

        /// <summary>The view direction: yaw 0 looks north (+z), +90 east; pitch looks down.</summary>
        public static Vec3 Forward(float yawDeg, float pitchDeg)
        {
            double y = yawDeg * Math.PI / 180.0, p = pitchDeg * Math.PI / 180.0;
            return new Vec3((float)(Math.Sin(y) * Math.Cos(p)), (float)-Math.Sin(p), (float)(Math.Cos(y) * Math.Cos(p)));
        }

        /// <summary>The camera position that looks at target from dist away.</summary>
        public static Vec3 Position(Vec3 target, float dist, float yawDeg, float pitchDeg)
        {
            return target - Forward(yawDeg, pitchDeg) * dist;
        }

        /// <summary>The moon: the direction its light travels (from the north-west, high, so shadows fall toward the camera and to the right).</summary>
        public static Vec3 MoonForward() { return Forward(150f, 38f); }
    }

    public sealed class FrontArtLayout
    {
        public const float Level = 0.5f;
        public const int OuterLevels = -3;   // the slab's cut edge goes down this many levels (1.5 units)
        public readonly int W, D;
        public readonly int[,] H;            // height in levels
        public readonly FaTex[,] Top, Side;
        public readonly bool[,] Masonry;     // wall tiles
        public readonly List<FaBox> Boxes = new List<FaBox>();
        public readonly List<FaLight> Lights = new List<FaLight>();
        public readonly List<FaActor> Actors = new List<FaActor>();
        /// <summary>Purchased pack monsters around the four (pictures not in git: unity/tools/front_art_packs.py); the scene skips a missing one.</summary>
        public readonly List<FaActor> Extras = new List<FaActor>();
        /// <summary>Attack spells between the figures (FrontArtSpells); the scene skips one whose art is missing.</summary>
        public readonly List<FaSpell> Spells = new List<FaSpell>();
        public float GateX, GateZ;

        public FrontArtLayout(int w, int d)
        {
            W = w; D = d;
            H = new int[w, d]; Top = new FaTex[w, d]; Side = new FaTex[w, d]; Masonry = new bool[w, d];
        }

        public bool Inside(int x, int z) { return x >= 0 && z >= 0 && x < W && z < D; }

        /// <summary>Ground height in units at a world point (0 outside the grid).</summary>
        public float GroundY(float x, float z)
        {
            int tx = (int)Math.Floor(x), tz = (int)Math.Floor(z);
            return Inside(tx, tz) ? H[tx, tz] * Level : 0f;
        }

        static float Rand(int x, int z, uint seed) { return FrontArtTex.Rand(x, z, seed); }

        FaBox Box(FaTex tex, float cx, float y0, float cz, float sx, float sy, float sz, float yaw, float tint, int seed, string tag)
        {
            return new FaBox { X0 = cx - sx / 2, X1 = cx + sx / 2, Z0 = cz - sz / 2, Z1 = cz + sz / 2, Y0 = y0, Y1 = y0 + sy, Yaw = yaw, Tex = tex, R = tint, G = tint, B = tint, Seed = seed, Tag = tag };
        }

        void Add(FaBox b) { Boxes.Add(b); }

        void Light(float x, float y, float z, float r, float g, float b, float range, float intensity, bool flame, int seed)
        {
            Lights.Add(new FaLight { X = x, Y = y, Z = z, R = r, G = g, B = b, Range = range, Intensity = intensity, Flame = flame, Seed = seed });
        }

        void FlameLight(float x, float y, float z, float fx, float fy, float fz, float size, float range, float intensity, int seed)
        {
            Lights.Add(new FaLight { X = x, Y = y, Z = z, R = 1.0f, G = 0.60f, B = 0.26f, Range = range, Intensity = intensity, Flame = true, Seed = seed, FlameX = fx, FlameY = fy, FlameZ = fz, FlameSize = size });
        }

        void Fill(int x0, int z0, int x1, int z1, int levels, FaTex top, FaTex side, bool masonry)
        {
            for (int z = z0; z <= z1; z++)
                for (int x = x0; x <= x1; x++)
                { H[x, z] = levels; Top[x, z] = top; Side[x, z] = side; Masonry[x, z] = masonry; }
        }

        void Brazier(float x, float z, int seed)
        {
            float y = GroundY(x, z);
            Add(Box(FaTex.Brick, x, y, z, 0.62f, 0.34f, 0.62f, 0f, 0.95f, seed, "brazier"));
            Add(Box(FaTex.Brick, x, y + 0.34f, z, 0.30f, 0.30f, 0.30f, 45f, 0.85f, seed + 1, "brazier"));
            Add(Box(FaTex.Cobble, x, y + 0.64f, z, 0.74f, 0.10f, 0.74f, 0f, 0.55f, seed + 2, "brazier"));
            Add(Box(FaTex.Cobble, x - 0.33f, y + 0.74f, z, 0.08f, 0.16f, 0.74f, 0f, 0.5f, seed + 3, "brazier"));
            Add(Box(FaTex.Cobble, x + 0.33f, y + 0.74f, z, 0.08f, 0.16f, 0.74f, 0f, 0.5f, seed + 4, "brazier"));
            Add(Box(FaTex.Cobble, x, y + 0.74f, z - 0.33f, 0.58f, 0.16f, 0.08f, 0f, 0.5f, seed + 5, "brazier"));
            Add(Box(FaTex.Cobble, x, y + 0.74f, z + 0.33f, 0.58f, 0.16f, 0.08f, 0f, 0.5f, seed + 6, "brazier"));
            Add(Box(FaTex.Coal, x, y + 0.74f, z, 0.56f, 0.07f, 0.56f, 12f, 1f, seed + 7, "coal"));
            FlameLight(x, y + 1.25f, z, x, y + 0.81f, z, 1f, 6.5f, 1.5f, seed);
        }

        void Torch(float x, float y, float z, int seed)
        {
            Add(Box(FaTex.Wood, x, y - 0.22f, z, 0.10f, 0.50f, 0.10f, 0f, 0.8f, seed, "torch"));
            Add(Box(FaTex.Brick, x, y - 0.28f, z - 0.02f, 0.22f, 0.07f, 0.22f, 0f, 0.7f, seed + 1, "torch"));
            Add(Box(FaTex.Coal, x, y + 0.27f, z, 0.14f, 0.05f, 0.14f, 0f, 1f, seed + 2, "coal"));
            FlameLight(x, y + 0.7f, z - 0.35f, x, y + 0.30f, z, 0.55f, 6.5f, 1.7f, seed);
        }

        void Pillar(float x, float z, float height, int seed)
        {
            float y = GroundY(x, z);
            Add(Box(FaTex.Brick, x, y, z, 1.05f, 0.30f, 1.05f, 0f, 0.9f, seed, "pillar"));
            float shaft = height - 0.30f - 0.28f;
            Add(Box(FaTex.Brick, x, y + 0.30f, z, 0.78f, shaft, 0.78f, 0f, 1f, seed + 1, "pillar"));
            Add(Box(FaTex.Flagstone, x, y + 0.30f + shaft, z, 1.0f, 0.28f, 1.0f, 0f, 0.95f, seed + 2, "pillar"));
            Add(Box(FaTex.Brick, x, y + 0.30f + shaft * 0.45f, z, 0.9f, 0.14f, 0.9f, 0f, 0.8f, seed + 3, "pillar"));
        }

        void Gravestone(float x, float z, float yaw, int seed)
        {
            float y = GroundY(x, z);
            float h = 0.7f + 0.35f * Rand(seed, 3, 11), w = 0.55f + 0.2f * Rand(seed, 4, 11);
            Add(Box(FaTex.Flagstone, x, y, z, w + 0.12f, 0.12f, 0.34f, yaw, 0.8f, seed, "grave"));
            Add(Box(FaTex.Flagstone, x, y + 0.12f, z, w, h, 0.20f, yaw, 0.95f, seed + 1, "grave"));
            Add(Box(FaTex.Flagstone, x, y + 0.12f + h, z, w * 0.62f, 0.14f, 0.20f, yaw, 1.0f, seed + 2, "grave"));
        }

        void Cross(float x, float z, float yaw, int seed)
        {
            float y = GroundY(x, z);
            Add(Box(FaTex.Flagstone, x, y, z, 0.5f, 0.12f, 0.5f, yaw, 0.75f, seed, "grave"));
            Add(Box(FaTex.Flagstone, x, y + 0.12f, z, 0.17f, 1.1f, 0.17f, yaw, 0.95f, seed + 1, "grave"));
            Add(Box(FaTex.Flagstone, x, y + 0.72f, z, 0.62f, 0.16f, 0.17f, yaw, 1.0f, seed + 2, "grave"));
        }

        void Rubble(float x, float z, int seed)
        {
            float s = 0.16f + 0.26f * Rand(seed, 1, 21);
            float y = GroundY(x, z);
            Add(Box(Rand(seed, 2, 21) < 0.6f ? FaTex.Brick : FaTex.Flagstone, x, y, z, s * 1.2f, s * 0.8f, s, Rand(seed, 3, 21) * 90f, 0.7f + 0.25f * Rand(seed, 5, 21), seed, "rubble"));
        }

        void DeadTree(float x, float z, int seed)
        {
            float y = GroundY(x, z);
            Add(Box(FaTex.Wood, x, y, z, 0.46f, 1.5f, 0.42f, 10f, 0.55f, seed, "tree"));
            Add(Box(FaTex.Wood, x + 0.05f, y + 1.5f, z, 0.32f, 1.0f, 0.30f, 38f, 0.55f, seed + 1, "tree"));
            Add(Box(FaTex.Wood, x - 0.30f, y + 1.55f, z + 0.1f, 0.9f, 0.13f, 0.13f, 25f, 0.55f, seed + 2, "tree"));
            Add(Box(FaTex.Wood, x + 0.32f, y + 1.95f, z - 0.1f, 0.8f, 0.11f, 0.11f, -35f, 0.55f, seed + 3, "tree"));
            Add(Box(FaTex.Wood, x + 0.1f, y + 2.35f, z, 0.20f, 0.5f, 0.20f, 70f, 0.5f, seed + 4, "tree"));
        }

        void Crate(float x, float z, float yaw, float size, float lift, int seed)
        {
            float y = GroundY(x, z) + lift;
            Add(Box(FaTex.Wood, x, y, z, size, size, size, yaw, 0.85f, seed, "crate"));
        }

        /// <summary>The scene: a 20 x 16 slab. The gate stands at x 8..11 in the back wall, the path runs from the south edge to it.</summary>
        public static FrontArtLayout Build()
        {
            var L = new FrontArtLayout(20, 16);
            const uint s = 1098;
            // outside the courtyard: dead grass and dirt
            for (int z = 0; z < L.D; z++)
                for (int x = 0; x < L.W; x++)
                {
                    float r = Rand(x, z, s);
                    L.Top[x, z] = r < 0.5f ? FaTex.DeadGrass : r < 0.8f ? FaTex.MossDirt : FaTex.Dirt;
                    L.Side[x, z] = FaTex.MossDirt;
                }
            // the courtyard floor, with cobble and dirt patches
            for (int z = 3; z <= 11; z++)
                for (int x = 3; x <= 16; x++)
                {
                    float r = Rand(x, z, s + 1);
                    L.Top[x, z] = r < 0.12f ? FaTex.Cobble : r < 0.19f ? FaTex.MossDirt : FaTex.Flagstone;
                    L.Side[x, z] = FaTex.Brick;
                }
            // the graveyard on the west side
            for (int z = 3; z <= 11; z++)
                for (int x = 3; x <= 6; x++)
                {
                    float r = Rand(x, z, s + 2);
                    L.Top[x, z] = r < 0.55f ? FaTex.DeadGrass : r < 0.85f ? FaTex.MossDirt : FaTex.Dirt;
                }
            // the cobble path from the south edge to the gate, ragged at its sides
            L.Fill(8, 0, 11, 11, 0, FaTex.Cobble, FaTex.Brick, false);
            for (int z = 0; z <= 11; z++)
            {
                if (Rand(7, z, s + 3) < 0.4f) L.Top[7, z] = FaTex.Cobble;
                if (Rand(12, z, s + 4) < 0.4f) L.Top[12, z] = FaTex.Cobble;
            }
            // the temple: a thick ragged wall at the back, higher at the gate
            for (int z = 12; z < L.D; z++)
                for (int x = 2; x <= 17; x++)
                {
                    int lv = 6 - (int)(Rand(x, z, s + 5) * 2.99f);
                    if (x < 4 || x > 15) lv -= 1 + (int)(Rand(x, z, s + 6) * 1.99f);
                    if (x == 7 || x == 12) lv = 7;
                    L.H[x, z] = Math.Max(2, lv); L.Top[x, z] = FaTex.Flagstone; L.Side[x, z] = FaTex.Brick; L.Masonry[x, z] = true;
                }
            // the gate: a passage 4 tiles wide and 2 deep
            for (int z = 12; z <= 13; z++)
                for (int x = 8; x <= 11; x++)
                { L.H[x, z] = 0; L.Top[x, z] = FaTex.Flagstone; L.Side[x, z] = FaTex.Brick; L.Masonry[x, z] = false; }
            L.GateX = 10f; L.GateZ = 12f;
            // the low wall ring: west and east sides and the south row, with a gap at the path and some broken tiles
            for (int z = 2; z <= 11; z++)
                foreach (int x in new[] { 2, 17 })
                    L.RingTile(x, z, s);
            for (int x = 3; x <= 16; x++)
                if (x < 8 || x > 11) L.RingTile(x, 2, s);
            // steps up to the gate
            L.Fill(7, 10, 12, 10, 1, FaTex.Flagstone, FaTex.Brick, true);
            L.Fill(7, 11, 12, 11, 2, FaTex.Flagstone, FaTex.Brick, true);
            for (int x = 8; x <= 11; x++) { L.Top[x, 10] = FaTex.Cobble; L.Top[x, 11] = FaTex.Cobble; L.Masonry[x, 10] = false; L.Masonry[x, 11] = false; }

            // ---- boxes ----
            // the walls beside the torches stay tall
            for (int z = 12; z < L.D; z++) { L.H[5, z] = 6; L.H[14, z] = 6; }
            // gate frame: door leaves at the back of the passage, a lintel, the door's iron-dark planks
            float gateY = 0f;
            L.Add(L.Box(FaTex.Wood, 9.0f, gateY, 13.75f, 1.95f, 2.5f, 0.28f, 0f, 0.7f, 3101, "gate"));
            L.Add(L.Box(FaTex.Wood, 11.0f, gateY, 13.75f, 1.95f, 2.5f, 0.28f, 0f, 0.7f, 3102, "gate"));
            L.Add(L.Box(FaTex.Brick, 10.0f, 2.5f, 13.0f, 4.4f, 0.55f, 2.0f, 0f, 0.95f, 3103, "gate"));
            L.Add(L.Box(FaTex.Brick, 10.0f, 3.05f, 12.9f, 4.7f, 0.2f, 2.1f, 0f, 0.8f, 3104, "gate"));
            L.Add(L.Box(FaTex.Brick, 7.75f, 0f, 12.1f, 0.62f, 3.55f, 0.55f, 0f, 1f, 3105, "gate"));
            L.Add(L.Box(FaTex.Brick, 12.25f, 0f, 12.1f, 0.62f, 3.55f, 0.55f, 0f, 1f, 3106, "gate"));
            L.Add(L.Box(FaTex.Wood, 10.0f, 1.0f, 13.58f, 0.10f, 0.4f, 0.08f, 0f, 0.5f, 3107, "gate"));
            // pillars flank the path
            L.Pillar(7.5f, 3.8f, 3.1f, 3200);
            L.Pillar(12.5f, 3.8f, 3.1f, 3210);
            L.Pillar(7.5f, 9.3f, 2.1f, 3220);   // broken
            L.Pillar(12.5f, 9.3f, 3.1f, 3230);
            L.Add(L.Box(FaTex.Brick, 7.9f, L.GroundY(7.5f, 8.5f), 8.6f, 0.4f, 0.3f, 0.4f, 25f, 0.8f, 3240, "rubble"));
            // braziers: the centre one between the fighters, two at the entrance, two on the steps
            L.Brazier(10.0f, 7.1f, 3300);
            L.Brazier(7.4f, 1.1f, 3310);
            L.Brazier(12.6f, 1.1f, 3320);
            L.Brazier(7.45f, 11.4f, 3330);
            L.Brazier(12.55f, 11.4f, 3340);
            // wall torches flank the gate on the face of the temple
            L.Torch(5.2f, 2.3f, 11.93f, 3400);
            L.Torch(14.8f, 2.3f, 11.93f, 3410);
            // graveyard
            float[,] graves = { { 3.7f, 4.2f }, { 5.2f, 3.6f }, { 6.0f, 5.2f }, { 4.3f, 6.1f }, { 5.7f, 7.1f }, { 3.6f, 8.2f }, { 5.0f, 9.3f }, { 6.1f, 10.3f }, { 3.9f, 10.6f } };
            for (int i = 0; i < graves.GetLength(0); i++)
                L.Gravestone(graves[i, 0], graves[i, 1], (Rand(i, 7, 31) - 0.5f) * 36f, 3500 + i * 10);
            L.Cross(4.6f, 4.9f, -12f, 3600);
            L.Cross(5.9f, 8.6f, 15f, 3610);
            L.DeadTree(3.9f, 9.1f, 3700);
            // the sarcophagus on the east side
            float sy = 0f;
            L.Add(L.Box(FaTex.Brick, 14.5f, sy, 6.6f, 2.5f, 0.38f, 1.3f, 8f, 0.9f, 3800, "sarcophagus"));
            L.Add(L.Box(FaTex.Flagstone, 14.5f, sy + 0.38f, 6.6f, 2.3f, 0.55f, 1.1f, 8f, 0.95f, 3801, "sarcophagus"));
            L.Add(L.Box(FaTex.Flagstone, 14.5f, sy + 0.93f, 6.6f, 2.0f, 0.18f, 0.8f, 8f, 1.05f, 3802, "sarcophagus"));
            L.Add(L.Box(FaTex.Brick, 15.15f, sy + 1.11f, 6.5f, 0.5f, 0.12f, 0.5f, 8f, 0.8f, 3803, "sarcophagus"));
            L.Light(14.5f, 1.55f, 6.2f, 0.32f, 0.95f, 0.85f, 5.0f, 0.9f, false, 3810);
            // an eerie glow in the gate passage
            L.Light(10.0f, 1.0f, 12.3f, 0.45f, 0.85f, 0.75f, 4.5f, 0.55f, false, 3820);
            // crates at the entrance
            L.Crate(14.1f, 3.9f, 15f, 0.72f, 0f, 3900);
            L.Crate(14.9f, 3.5f, -10f, 0.62f, 0f, 3901);
            L.Crate(14.4f, 3.8f, 30f, 0.5f, 0.72f, 3902);
            // rubble along the walls and the broken ring
            for (int i = 0; i < 42; i++)
            {
                float rx = 2.2f + Rand(i, 1, s + 40) * 15.6f, rz = 2.2f + Rand(i, 2, s + 40) * 9.6f;
                int tx = (int)rx, tz = (int)rz;
                if (L.Masonry[tx, tz] && L.H[tx, tz] > 0) continue;
                bool nearWall = rz > 9.2f || rx < 3.4f || rx > 16.6f || rz < 3.4f;
                if (!nearWall && Rand(i, 3, s + 40) < 0.7f) continue;
                if (rx > 8f && rx < 12f && rz < 11f) continue;   // keep the path clear
                L.Rubble(rx, rz, 4000 + i);
            }

            // ---- characters: the knight and the mage west of the centre brazier, the skeleton and the ghoul east of it, 3/4 views to the camera ----
            L.Actors.Add(new FaActor { Name = "Knight", Folder = "knight", X = 7.7f, Z = 7.9f, FaceX = 1f, FaceZ = -0.9f });
            L.Actors.Add(new FaActor { Name = "Mage", Folder = "mage", X = 8.9f, Z = 6.2f, FaceX = 1f, FaceZ = 0f });
            L.Actors.Add(new FaActor { Name = "Skeleton", Folder = "skeleton", X = 12.3f, Z = 7.8f, FaceX = -1f, FaceZ = -0.9f, Monster = true });
            L.Actors.Add(new FaActor { Name = "Ghoul", Folder = "ghoul", X = 11.1f, Z = 6.1f, FaceX = -1f, FaceZ = -0.1f, Monster = true });
            // ---- extras: pack monsters (64 texels at 40 per unit, the 32-texel skeleton at 32): the horde east, ghosts among the
            // graves facing it, two cultists before the gate looking down the path ----
            Action<string, string, float, float, float, float, float> extra = (name, folder, x, z, fx, fz, units) =>
                L.Extras.Add(new FaActor { Name = name, Folder = "pk_" + folder, X = x, Z = z, FaceX = fx, FaceZ = fz, Units = units, Monster = true });
            // patrols: the monster walks from its spot to (wx, wz) and back on flat open ground (FrontArtWalk)
            Action<string, float, float> patrol = (name, wx, wz) =>
            {
                int k = L.Extras.FindIndex(e => e.Name == name);
                var e2 = L.Extras[k];
                e2.Walks = true; e2.WalkX = wx; e2.WalkZ = wz;
                L.Extras[k] = e2;
            };
            extra("Fire demon", "fire_demon", 13.6f, 9.0f, -1f, -0.6f, 1.6f);
            extra("Winged demon", "winged_demon", 15.5f, 9.7f, -1f, -0.4f, 1.6f);
            extra("Vampire", "vampire", 13.4f, 5.0f, -1f, 0.3f, 1.6f);
            extra("Werewolf", "werewolf", 16.0f, 5.2f, -1f, 0.2f, 1.6f);
            extra("Headless rider", "headless", 15.7f, 8.2f, -1f, -0.3f, 1.6f);
            extra("Frost demon", "frost_demon", 14.7f, 4.9f, -1f, 0.5f, 1.6f);
            extra("Rat king", "rat_king", 13.0f, 3.0f, -1f, 0.6f, 1.6f);
            extra("Goblin shaman", "goblin_shaman", 16.0f, 10.9f, -1f, -0.6f, 1.6f);
            extra("Lizard mystic", "lizard_mystic", 13.9f, 10.7f, -1f, -0.5f, 1.6f);
            extra("Armored skeleton", "armored_skeleton", 13.3f, 7.75f, -1f, 0.4f, 1.0f);
            extra("Ghost king", "ghost_king", 4.6f, 7.4f, 1f, -0.3f, 1.6f);
            extra("Ghost knight", "ghost_knight", 6.2f, 4.3f, 1f, 0.4f, 1.6f);
            extra("Red cultist", "cultist_red", 9.0f, 9.4f, -0.2f, -1f, 1.6f);
            extra("Dark cultist", "cultist_dark", 11.0f, 9.4f, 0.2f, -1f, 1.6f);
            patrol("Fire demon", 14.6f, 9.0f);
            patrol("Winged demon", 16.3f, 9.7f);
            patrol("Vampire", 12.2f, 5.0f);
            patrol("Werewolf", 16.0f, 4.0f);
            patrol("Headless rider", 16.4f, 8.2f);
            patrol("Frost demon", 14.7f, 5.6f);
            patrol("Rat king", 11.6f, 3.0f);
            patrol("Lizard mystic", 14.9f, 10.7f);
            patrol("Ghost king", 4.6f, 8.6f);
            patrol("Ghost knight", 6.2f, 3.0f);
            patrol("Red cultist", 9.0f, 8.4f);
            patrol("Dark cultist", 11.0f, 8.4f);
            // ---- attack spells: the horde, the ghost king and the cultists at the knight and the mage; the mage answers ----
            Action<string, string, string, string, float, float, float, float, float> spell = (caster, target, missile, impact, r, g, b, offset, period) =>
                L.Spells.Add(new FaSpell { Caster = caster, Target = target, Missile = missile, Impact = impact, R = r, G = g, B = b, Offset = offset, Period = period });
            spell("Fire demon", "Knight", "fireball", "fireball", 1.0f, 0.45f, 0.12f, 0.3f, 0f);
            spell("Frost demon", "Mage", "frost", "frost", 0.35f, 0.8f, 1.0f, 0.35f, 0f);
            spell("Lizard mystic", "Knight", "arcane", "arcane", 0.7f, 0.35f, 1.0f, 0.3f, 0f);
            spell("Goblin shaman", "Mage", "skull_necrotic", "skull_necrotic", 0.45f, 1.0f, 0.35f, 0.6f, 4.2f);
            spell("Red cultist", "Knight", "blood", "blood", 1.0f, 0.15f, 0.15f, 0.3f, 0f);
            spell("Dark cultist", "Mage", "shadow", "shadow", 0.6f, 0.25f, 1.0f, 0.35f, 0f);
            spell("Ghost king", "Knight", "skull_spirit", "skull_spirit", 0.4f, 1.0f, 0.85f, 0.3f, 0f);
            spell("Mage", "Fire demon", "holy", "holy", 1.0f, 0.85f, 0.4f, 1.2f, 3.6f);
            foreach (var list in new[] { L.Actors, L.Extras })
                for (int i = 0; i < list.Count; i++)
                {
                    var a = list[i];
                    a.Y = L.GroundY(a.X, a.Z);
                    list[i] = a;
                }
            return L;
        }

        void RingTile(int x, int z, uint s)
        {
            float r = Rand(x, z, s + 8);
            if (r < 0.16f) return;   // gone
            int lv = r < 0.34f ? 1 : 2;
            H[x, z] = lv; Top[x, z] = FaTex.Flagstone; Side[x, z] = FaTex.Brick; Masonry[x, z] = true;
        }
    }

    /// <summary>Quads of one texture kind, ready for a mesh.</summary>
    public sealed class FaBucket
    {
        public readonly List<float> V = new List<float>(), N = new List<float>(), UV = new List<float>(), C = new List<float>();
        public readonly List<int> T = new List<int>();
        public int Quads => T.Count / 6;
        public int Vertices => V.Count / 3;
    }

    public static class FrontArtMesher
    {
        const float Tile = FrontArtTex.TileUnits;

        sealed class Quads
        {
            public readonly FaBucket[] B = new FaBucket[(int)FaTex.Count];
            public Quads() { for (int i = 0; i < B.Length; i++) B[i] = new FaBucket(); }

            // corners a (bottom left), b (bottom right), c (top right), d (top left) as seen from the front; nx..nz the facing; colours per corner
            public void Quad(FaTex tex, Vec3 a, Vec3 b, Vec3 c, Vec3 d, Vec3 n, float[] u, float[] v, float[] col)
            {
                var bk = B[(int)tex];
                // the geometric facing must match the normal, or the quad is wound the other way
                float cx = (d.Y - a.Y) * (c.Z - a.Z) - (d.Z - a.Z) * (c.Y - a.Y);
                float cy = (d.Z - a.Z) * (c.X - a.X) - (d.X - a.X) * (c.Z - a.Z);
                float cz = (d.X - a.X) * (c.Y - a.Y) - (d.Y - a.Y) * (c.X - a.X);
                bool flip = cx * n.X + cy * n.Y + cz * n.Z < 0f;
                var p = new[] { a, b, c, d };
                int i0 = bk.Vertices;
                for (int k = 0; k < 4; k++)
                {
                    bk.V.Add(p[k].X); bk.V.Add(p[k].Y); bk.V.Add(p[k].Z);
                    bk.N.Add(n.X); bk.N.Add(n.Y); bk.N.Add(n.Z);
                    bk.UV.Add(u[k]); bk.UV.Add(v[k]);
                    bk.C.Add(col[k * 4]); bk.C.Add(col[k * 4 + 1]); bk.C.Add(col[k * 4 + 2]); bk.C.Add(col[k * 4 + 3]);
                }
                // clockwise seen from the front: (a, d, c) and (a, c, b); the other way round when the quad is wound backwards
                if (!flip) { bk.T.Add(i0); bk.T.Add(i0 + 3); bk.T.Add(i0 + 2); bk.T.Add(i0); bk.T.Add(i0 + 2); bk.T.Add(i0 + 1); }
                else { bk.T.Add(i0); bk.T.Add(i0 + 1); bk.T.Add(i0 + 2); bk.T.Add(i0); bk.T.Add(i0 + 2); bk.T.Add(i0 + 3); }
            }
        }

        static float[] Col(float r0, float r1, float r2, float r3, float tr, float tg, float tb)
        {
            return new[] { r0 * tr, r0 * tg, r0 * tb, 1f, r1 * tr, r1 * tg, r1 * tb, 1f, r2 * tr, r2 * tg, r2 * tb, 1f, r3 * tr, r3 * tg, r3 * tb, 1f };
        }

        static float AoValue(bool side1, bool side2, bool corner)
        {
            int v = side1 && side2 ? 0 : 3 - ((side1 ? 1 : 0) + (side2 ? 1 : 0) + (corner ? 1 : 0));
            return 0.6f + 0.4f * (v / 3f);
        }

        /// <summary>The terrain: a top quad per tile, side quads only where the neighbour is lower, the slab's cut edge, and the outer ground.
        /// One FaBucket per texture kind.</summary>
        public static FaBucket[] Terrain(FrontArtLayout L)
        {
            var q = new Quads();
            for (int z = 0; z < L.D; z++)
                for (int x = 0; x < L.W; x++)
                {
                    int h = L.H[x, z];
                    float y = h * FrontArtLayout.Level;
                    float tint = 0.86f + 0.14f * FrontArtTex.Rand(x, z, 77);
                    // top, with ambient occlusion at the corners from higher neighbours
                    Func<int, int, bool> hi = (dx, dz) => L.Inside(x + dx, z + dz) && L.H[x + dx, z + dz] > h;
                    float ao00 = AoValue(hi(-1, 0), hi(0, -1), hi(-1, -1)), ao10 = AoValue(hi(1, 0), hi(0, -1), hi(1, -1));
                    float ao11 = AoValue(hi(1, 0), hi(0, 1), hi(1, 1)), ao01 = AoValue(hi(-1, 0), hi(0, 1), hi(-1, 1));
                    q.Quad(L.Top[x, z], new Vec3(x, y, z), new Vec3(x + 1, y, z), new Vec3(x + 1, y, z + 1), new Vec3(x, y, z + 1), new Vec3(0, 1, 0),
                        new[] { x / Tile, (x + 1) / Tile, (x + 1) / Tile, x / Tile }, new[] { z / Tile, z / Tile, (z + 1) / Tile, (z + 1) / Tile },
                        Col(ao00, ao10, ao11, ao01, tint, tint, tint));
                    // sides: west, east, south, north
                    int[] dxs = { -1, 1, 0, 0 }, dzs = { 0, 0, -1, 1 };
                    for (int k = 0; k < 4; k++)
                    {
                        int nx = x + dxs[k], nz = z + dzs[k];
                        bool inside = L.Inside(nx, nz);
                        int nh = inside ? L.H[nx, nz] : FrontArtLayout.OuterLevels;
                        if (nh >= h) continue;
                        float ny = nh * FrontArtLayout.Level;
                        Vec3 n = new Vec3(dxs[k], 0, dzs[k]);
                        // the face's corners: left and right as seen from the front
                        float x0, z0, x1, z1;
                        if (k == 0) { x0 = x; z0 = z + 1; x1 = x; z1 = z; }
                        else if (k == 1) { x0 = x + 1; z0 = z; x1 = x + 1; z1 = z + 1; }
                        else if (k == 2) { x0 = x; z0 = z; x1 = x + 1; z1 = z; }
                        else { x0 = x + 1; z0 = z + 1; x1 = x; z1 = z + 1; }
                        float ua = k < 2 ? z0 : x0, ub = k < 2 ? z1 : x1;
                        if (inside)
                            SideQuad(q, L.Side[x, z], x0, z0, x1, z1, ny, y, ua / Tile, ub / Tile, n, tint, 0.62f);
                        else
                        {
                            float cut = 0f;
                            if (y > cut) SideQuad(q, L.Side[x, z], x0, z0, x1, z1, cut, y, ua / Tile, ub / Tile, n, tint, 0.85f);
                            SideQuad(q, FaTex.MossDirt, x0, z0, x1, z1, ny, Math.Min(y, cut), ua / Tile, ub / Tile, n, tint, 0.45f);
                        }
                    }
                }
            // the outer ground under the slab's edge, far and dark; the fog takes it
            float oy = FrontArtLayout.OuterLevels * FrontArtLayout.Level, e = 120f;
            q.Quad(FaTex.DeadGrass, new Vec3(-e, oy, -e), new Vec3(L.W + e, oy, -e), new Vec3(L.W + e, oy, L.D + e), new Vec3(-e, oy, L.D + e), new Vec3(0, 1, 0),
                new[] { -e / Tile, (L.W + e) / Tile, (L.W + e) / Tile, -e / Tile }, new[] { -e / Tile, -e / Tile, (L.D + e) / Tile, (L.D + e) / Tile },
                Col(0.5f, 0.5f, 0.5f, 0.5f, 0.8f, 0.85f, 1f));
            return q.B;
        }

        static void SideQuad(Quads q, FaTex tex, float x0, float z0, float x1, float z1, float yb, float yt, float ua, float ub, Vec3 n, float tint, float bottomAo)
        {
            if (yt - yb < 1e-4f) return;
            q.Quad(tex, new Vec3(x0, yb, z0), new Vec3(x1, yb, z1), new Vec3(x1, yt, z1), new Vec3(x0, yt, z0), n,
                new[] { ua, ub, ub, ua }, new[] { yb / Tile, yb / Tile, yt / Tile, yt / Tile },
                Col(bottomAo, bottomAo, 1f, 1f, tint, tint, tint));
        }

        /// <summary>The boxes: top and four sides (the bottom rests on the ground and is dropped). One FaBucket per texture kind.</summary>
        public static FaBucket[] Boxes(IList<FaBox> boxes)
        {
            var q = new Quads();
            foreach (var b in boxes)
            {
                float cx = (b.X0 + b.X1) / 2f, cz = (b.Z0 + b.Z1) / 2f, hx = (b.X1 - b.X0) / 2f, hz = (b.Z1 - b.Z0) / 2f;
                double yaw = b.Yaw * Math.PI / 180.0;
                float cs = (float)Math.Cos(yaw), sn = (float)Math.Sin(yaw);
                float ox = FrontArtTex.Rand(b.Seed, 1, 5) * Tile, oz = FrontArtTex.Rand(b.Seed, 2, 5) * Tile;
                // rotate an offset (dx, dz) about Y: +z turns toward +x
                Func<float, float, Vec3> P = (dx, dz) => new Vec3(cx + dx * cs + dz * sn, 0f, cz - dx * sn + dz * cs);
                Func<float, float, float, Vec3> At = (dx, y, dz) => { var p = P(dx, dz); return new Vec3(p.X, y, p.Z); };
                float aoB = b.Y0 < 0.45f && (b.Tag == null || b.Tag != "crate" || b.Y0 < 0.01f) ? 0.7f : 1f;
                // top
                q.Quad(b.Tex, At(-hx, b.Y1, -hz), At(hx, b.Y1, -hz), At(hx, b.Y1, hz), At(-hx, b.Y1, hz), new Vec3(0, 1, 0),
                    new[] { ox, ox + 2 * hx, ox + 2 * hx, ox }, new[] { oz, oz, oz + 2 * hz, oz + 2 * hz }, Col(1f, 1f, 1f, 1f, b.R, b.G, b.B));
                // sides: south (-z), east (+x), north (+z), west (-x), as seen from outside
                for (int k = 0; k < 4; k++)
                {
                    float ax, az, bx, bz;   // left and right corner as seen from outside
                    Vec3 n;
                    if (k == 0) { ax = -hx; az = -hz; bx = hx; bz = -hz; n = new Vec3(0, 0, -1); }
                    else if (k == 1) { ax = hx; az = -hz; bx = hx; bz = hz; n = new Vec3(1, 0, 0); }
                    else if (k == 2) { ax = hx; az = hz; bx = -hx; bz = hz; n = new Vec3(0, 0, 1); }
                    else { ax = -hx; az = hz; bx = -hx; bz = -hz; n = new Vec3(-1, 0, 0); }
                    // normal rotated like the corners: (nx, nz) -> (nx cs + nz sn, -nx sn + nz cs)
                    n = new Vec3(n.X * cs + n.Z * sn, 0f, -n.X * sn + n.Z * cs);
                    float width = k % 2 == 0 ? 2 * hx : 2 * hz;
                    float u0 = ox + k * 1.7f;
                    q.Quad(b.Tex, At(ax, b.Y0, az), At(bx, b.Y0, bz), At(bx, b.Y1, bz), At(ax, b.Y1, az), n,
                        new[] { u0, u0 + width, u0 + width, u0 }, new[] { b.Y0 / Tile, b.Y0 / Tile, b.Y1 / Tile, b.Y1 / Tile },
                        Col(aoB, aoB, 1f, 1f, b.R, b.G, b.B));
                }
            }
            return q.B;
        }

        /// <summary>A short report of a mesh set: quads per texture kind.</summary>
        public static int TotalQuads(FaBucket[] buckets) { int n = 0; foreach (var b in buckets) n += b.Quads; return n; }
    }
}
