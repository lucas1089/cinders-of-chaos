// 3D characters in the HD-2D view: which model a creature gets, where it stands, which way it faces, how big it is, the dark
// fantasy tint and which animation clip is the idle one. Pure C#, no Unity types (Unity/Hd2dChars3d.cs applies it).
// Models: Resources/Chars3d/NAME.fbx, the CC0 RPG Character Pack by Quaternius (docs/CREDITS.md).
// Axes as in Hd2dRuins: x east, z north (screen up: z = -(tile y - origin y)), y up; the camera is on the south side.
using System;

namespace Chaos.Core
{
    public static class Hd2dChars
    {
        /// <summary>The model files we ship, Resources/Chars3d/NAME. The player gets the first one.</summary>
        public static readonly string[] Models = { "Warrior", "Cleric", "Wizard" };
        public const string PlayerModel = "Warrior";
        /// <summary>A character is this many tiles tall (1 tile = 1 unit).</summary>
        public const float Height = 1.7f;
        /// <summary>Added to every yaw: the pack's models face +z in Unity (Blender export), so 0.</summary>
        public const float ModelYaw = 0f;
        /// <summary>Dark fantasy restyle of the bright textures: colour multiplier and the share pulled to grey.</summary>
        public const float Dim = 0.75f, Desaturate = 0.2f;

        static int Hash(uint a, int b)
        {
            unchecked
            {
                int h = (int)a * 73856093 ^ b * 19349663 ^ 0x5bd1e995;
                h ^= h >> 13; h *= 0x5bd1e995; h ^= h >> 15;
                return h & 0x7fffffff;
            }
        }

        /// <summary>Replaced by a model: a creature drawn as an outfit (look type), not as an item.</summary>
        public static bool Replaces(Creature c) => c != null && c.Outfit != null && c.Outfit.LookType != 0;

        /// <summary>The model of a creature: the player is the Warrior; the others hash their look type (their id when
        /// the look is 0) onto the models that are left.</summary>
        public static string ModelFor(Creature c, bool isPlayer)
        {
            if (isPlayer) return PlayerModel;
            int others = Models.Length - 1;
            int look = c.Outfit != null ? c.Outfit.LookType : 0;
            int k = Hash(look != 0 ? (uint)look : c.Id, look != 0 ? 1 : 2) % others;
            return Models[1 + k];
        }

        /// <summary>Yaw in degrees round y, 0 = +z (north, away from the camera), 90 = east, 180 = south, 270 = west.</summary>
        public static float Yaw(Dir d)
        {
            switch (d)
            {
                case Dir.North: return 0f;
                case Dir.NorthEast: return 45f;
                case Dir.East: return 90f;
                case Dir.SouthEast: return 135f;
                case Dir.South: return 180f;
                case Dir.SouthWest: return 225f;
                case Dir.West: return 270f;
                case Dir.NorthWest: return 315f;
            }
            return 180f;
        }

        /// <summary>The centre of the tile cell at drawn tile (x, y) (may be fractional while walking).</summary>
        public static float X(Pos origin, float x) => x - origin.X + 0.5f;
        public static float Z(Pos origin, float y) => -(y - origin.Y) - 0.5f;

        /// <summary>Scale that makes a model of `modelHeight` units stand Height tall; 1 when the height is unknown.</summary>
        public static float ScaleFor(float modelHeight) => modelHeight > 1e-4f && !float.IsNaN(modelHeight) ? Height / modelHeight : 1f;

        /// <summary>The material colour that multiplies the texture: Dim, with Desaturate of the base colour pulled to its grey.</summary>
        public static void Tint(float r, float g, float b, out float tr, out float tg, out float tb)
        {
            float grey = 0.299f * r + 0.587f * g + 0.114f * b;
            tr = (r + (grey - r) * Desaturate) * Dim;
            tg = (g + (grey - g) * Desaturate) * Dim;
            tb = (b + (grey - b) * Desaturate) * Dim;
        }

        /// <summary>The idle clip among the clip names of a model ("CharacterArmature|Idle", "...|Idle_Weapon", ...): plain
        /// Idle first, then any Idle that is not an attack, then any name with Idle; -1 when there is none.</summary>
        public static int IdleClip(string[] names)
        {
            int best = -1, rank = 9;
            for (int i = 0; i < names.Length; i++)
            {
                string n = names[i] ?? "";
                if (n.StartsWith("__preview__", StringComparison.Ordinal)) continue;
                int bar = n.LastIndexOf('|');
                string s = (bar >= 0 ? n.Substring(bar + 1) : n).ToLowerInvariant();
                int r = s == "idle" ? 0 : s.StartsWith("idle", StringComparison.Ordinal) && s.IndexOf("attack", StringComparison.Ordinal) < 0 ? 1 : s.IndexOf("idle", StringComparison.Ordinal) >= 0 ? 2 : 9;
                if (r < rank) { rank = r; best = i; }
            }
            return best;
        }

        /// <summary>Where in the idle clip a creature is sampled (seconds): its own phase, so a group does not breathe in step.</summary>
        public static float IdleTime(uint id, float length) => length <= 0f ? 0f : length * (Hash(id, 3) % 1000) / 1000f;

        /// <summary>The texture name for a material: its own name when it is a texture name of the pack, else the model's body
        /// texture; a weapon sub-mesh ("Warrior_Sword_Texture") is told apart by its material name.</summary>
        public static string TextureFor(string model, string materialName)
        {
            string m = (materialName ?? "").Replace(" (Instance)", "").Trim();
            if (m.StartsWith(model + "_", StringComparison.Ordinal) && m.EndsWith("_Texture", StringComparison.Ordinal)) return m;
            if (m.StartsWith(model + "_", StringComparison.Ordinal)) return m + "_Texture";
            return model + "_Texture";
        }
    }
}
