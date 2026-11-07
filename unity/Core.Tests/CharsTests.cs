// Checks of the 3D characters mapping (Core/Hd2dChars.cs): models, yaw, position, scale, tint and the idle clip.
using System;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class CharsTests
    {
        static bool Near(float a, float b, float eps = 1e-3f) => Math.Abs(a - b) <= eps;

        static Creature Mk(uint id, int look, Dir d = Dir.South) => new Creature { Id = id, Outfit = new Outfit(look, 0, 0, 0, 0), Direction = d };

        public static void Run(Action<bool, string> check)
        {
            check(Hd2dChars.ModelFor(Mk(1, 128), true) == "Warrior" && Hd2dChars.ModelFor(Mk(9, 5), true) == "Warrior", "chars: the player is the Warrior, whatever the look");
            var picks = Enumerable.Range(1, 200).Select(l => Hd2dChars.ModelFor(Mk(2, l), false)).ToList();
            check(picks.All(p => Array.IndexOf(Hd2dChars.Models, p) > 0), "chars: others never get the player's model");
            check(Hd2dChars.Models.Skip(1).All(m => picks.Contains(m)), "chars: every other model is picked for some look");
            check(Hd2dChars.ModelFor(Mk(2, 130), false) == Hd2dChars.ModelFor(Mk(77, 130), false), "chars: the same look gets the same model, whatever the id");
            check(Hd2dChars.ModelFor(Mk(5, 0), false) == Hd2dChars.ModelFor(Mk(5, 0), false), "chars: look 0 picks by id, stable");
            check(Hd2dChars.Replaces(Mk(2, 129)) && !Hd2dChars.Replaces(Mk(2, 0)) && !Hd2dChars.Replaces(null), "chars: an outfit creature is replaced, an item look stays a sprite");

            check(Near(Hd2dChars.Yaw(Dir.North), 0f) && Near(Hd2dChars.Yaw(Dir.East), 90f) && Near(Hd2dChars.Yaw(Dir.South), 180f) && Near(Hd2dChars.Yaw(Dir.West), 270f), "chars: north faces +z (away from the camera), then 90 degrees clockwise seen from above");
            check(Enum.GetValues(typeof(Dir)).Cast<Dir>().Select(Hd2dChars.Yaw).Distinct().Count() == 8, "chars: 8 facings, 8 yaws");

            var o = new Pos(100, 100, 7);
            check(Near(Hd2dChars.X(o, 100), 0.5f) && Near(Hd2dChars.Z(o, 100), -0.5f), "chars: the origin tile's centre");
            check(Near(Hd2dChars.X(o, 103), Hd2dRuins.TileX(o, 103)) && Near(Hd2dChars.Z(o, 98), Hd2dRuins.TileZ(o, 98)), "chars: same tile mapping as the ruins");
            check(Hd2dChars.Z(o, 98) > Hd2dChars.Z(o, 102), "chars: north (smaller y) is further from the camera (larger z)");

            check(Near(Hd2dChars.ScaleFor(2f) * 2f, Hd2dChars.Height) && Hd2dChars.Height >= 1.6f && Hd2dChars.Height <= 1.8f, "chars: scaled to 1.6-1.8 tiles");
            check(Near(Hd2dChars.ScaleFor(0f), 1f) && Near(Hd2dChars.ScaleFor(float.NaN), 1f), "chars: an unknown model height keeps scale 1");

            Hd2dChars.Tint(1f, 1f, 1f, out float r, out float g, out float b);
            check(Near(r, 0.75f) && Near(g, 0.75f) && Near(b, 0.75f), "chars: a white tint becomes 0.75 grey");
            Hd2dChars.Tint(1f, 0.2f, 0.2f, out r, out g, out b);
            check(r < 0.75f && r > g && (r - g) < (1f - 0.2f) * 0.75f, "chars: a red tint is dimmed and a little less saturated");

            string[] names = { "__preview__x", "CharacterArmature|Death", "CharacterArmature|Idle_Attacking", "CharacterArmature|Idle_Weapon", "CharacterArmature|Idle", "CharacterArmature|Walk" };
            check(Hd2dChars.IdleClip(names) == 4, "chars: plain Idle is the idle clip");
            check(Hd2dChars.IdleClip(new[] { "CharacterArmature|Idle_Attacking", "CharacterArmature|Idle_Weapon" }) == 1, "chars: Idle_Weapon beats Idle_Attacking");
            check(Hd2dChars.IdleClip(new[] { "CharacterArmature|Idle_Attacking", "Walk" }) == 0, "chars: any idle is better than none");
            check(Hd2dChars.IdleClip(new[] { "Walk", "Run" }) == -1 && Hd2dChars.IdleClip(new string[0]) == -1, "chars: no idle clip, no pick (bind pose)");
            float t = Hd2dChars.IdleTime(5, 2f);
            check(t >= 0f && t < 2f && Near(t, Hd2dChars.IdleTime(5, 2f)) && Near(Hd2dChars.IdleTime(5, 0f), 0f), "chars: the idle sample time is inside the clip and stable");

            check(Hd2dChars.TextureFor("Warrior", "Warrior_Texture") == "Warrior_Texture", "chars: body material binds the body texture");
            check(Hd2dChars.TextureFor("Warrior", "Warrior_Sword_Texture (Instance)") == "Warrior_Sword_Texture", "chars: the weapon material binds the weapon texture");
            check(Hd2dChars.TextureFor("Cleric", "Cleric_Staff") == "Cleric_Staff_Texture" && Hd2dChars.TextureFor("Cleric", "Material") == "Cleric_Texture", "chars: other names fall back to the body texture");
        }
    }
}
