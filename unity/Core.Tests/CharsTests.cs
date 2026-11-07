// Checks of the 3D characters mapping (Core/Hd2dChars.cs): the 21 classes, the monster rules over every monster name of the server,
// size, yaw, position, tint, hand bones, the idle clip, the pixel font of the label overlay and the line-up of the cast screenshot.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class CharsTests
    {
        static bool Near(float a, float b, float eps = 1e-3f) => Math.Abs(a - b) <= eps;

        static Creature Mk(uint id, int look, Dir d = Dir.South, byte type = 0, string name = "") =>
            new Creature { Id = id, Outfit = new Outfit(look, 0, 0, 0, 0), Direction = d, Type = type, Name = name };

        static string FindRoot()
        {
            foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
                for (var d = new DirectoryInfo(start); d != null; d = d.Parent)
                    if (Directory.Exists(Path.Combine(d.FullName, "server", "data", "monster")) && File.Exists(Path.Combine(d.FullName, "ROADMAP.md"))) return d.FullName;
            return null;
        }

        // the nodes each adventurer FBX carries (the weapons and shields of the KayKit Adventurers pack)
        static readonly Dictionary<string, string[]> Nodes = new Dictionary<string, string[]>
        {
            { "Knight", new[] { "1H_Sword", "1H_Sword_Offhand", "2H_Sword", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield" } },
            { "Barbarian", new[] { "1H_Axe", "1H_Axe_Offhand", "2H_Axe", "Barbarian_Round_Shield", "Mug" } },
            { "Mage", new[] { "1H_Wand", "2H_Staff", "Spellbook", "Spellbook_open" } },
            { "Rogue", new[] { "1H_Crossbow", "2H_Crossbow", "Knife", "Knife_Offhand", "Throwable" } },
            { "RogueHooded", new[] { "1H_Crossbow", "2H_Crossbow", "Knife", "Knife_Offhand", "Throwable" } },
        };
        // the weapon files the fetch script brings for the skeletons (unity/tools/fetch_3d_assets.py)
        static readonly string[] SkeletonItems = { "Skeleton_Blade", "Skeleton_Axe", "Skeleton_Staff", "Skeleton_Crossbow", "Skeleton_Shield_Small_A", "Skeleton_Shield_Large_A" };
        static readonly string[] KayModels = { "Knight", "Barbarian", "Mage", "Rogue", "RogueHooded", "Skeleton_Warrior", "Skeleton_Mage", "Skeleton_Rogue", "Skeleton_Minion" };

        static bool ValidItems(CharSpec s)
        {
            if (s.Items == null) return false;
            if (Nodes.TryGetValue(s.Model, out var nodes)) return s.Items.All(i => nodes.Contains(i));
            return s.Model.StartsWith("Skeleton_", StringComparison.Ordinal) && s.Items.All(i => SkeletonItems.Contains(i));
        }

        static bool ValidSpec(CharSpec s) =>
            s != null && KayModels.Contains(s.Model) && Hd2dChars.Models.Contains(s.Fallback) && ValidItems(s)
            && s.Scale >= 0.8f && s.Scale <= 1.2f && s.Dim >= 0.5f && s.Dim <= 1f
            && new[] { s.R, s.G, s.B }.All(v => v >= 0.5f && v <= 1.4f);

        public static void Run(Action<bool, string> check)
        {
            // ---- the 21 classes
            var ids = Hd2dChars.Classes.Select(c => c.Id).ToList();
            check(Hd2dChars.Classes.Length == 21 && ids.Distinct().Count() == 21, "chars: 21 classes with 21 different vocation ids");
            check(Hd2dChars.Classes.All(c => ValidSpec(c.Spec)), "chars: every class has a valid model, fallback, items, tint and size");
            check(Hd2dChars.Classes.Select(c => c.Spec.Label).Distinct().Count() == 21, "chars: every class has its own label");
            check(Hd2dChars.Classes.Select(c => c.Group).Distinct().Count() == 7, "chars: seven class groups");
            check(Hd2dChars.Classes.GroupBy(c => c.Group).All(g => g.Count() == 3), "chars: three classes per group");
            check(Hd2dChars.Classes.Select(c => c.Spec).Select(s => s.Model + "|" + string.Join(",", s.Items) + "|" + s.R + "," + s.G + "," + s.B).Distinct().Count() == 21, "chars: no two classes look alike (model, items, tint)");
            check(Hd2dChars.Classes.Select(c => c.Spec.Model).Distinct().Count() >= 7, "chars: the 21 classes use at least 7 models");
            check(Hd2dChars.ClassOf(8).Name == "Juggernaut" && Hd2dChars.ClassOf(21).Name == "Lich" && Hd2dChars.ClassOf(99) == null, "chars: class lookup by vocation id");
            foreach (int id in new[] { 4, 8, 14 }) check(new[] { "Knight", "Barbarian" }.Contains(Hd2dChars.ClassOf(id).Spec.Model), "chars: the heavy melee classes are Knight or Barbarian (" + id + ")");
            foreach (int id in new[] { 1, 5, 10, 20, 19 }) check(Hd2dChars.ClassOf(id).Spec.Model == "Mage", "chars: the casters are the Mage (" + id + ")");
            foreach (int id in new[] { 3, 7, 15, 11, 12 }) check(Hd2dChars.ClassOf(id).Spec.Model.StartsWith("Rogue", StringComparison.Ordinal), "chars: ranged and stealth classes are Rogue models (" + id + ")");
            foreach (int id in new[] { 23, 24, 25 }) check(Hd2dChars.ClassOf(id).Spec.Model == "Knight" && Hd2dChars.ClassOf(id).Spec.Dim > Hd2dChars.Dim, "chars: the holy classes are the Knight in a light tint (" + id + ")");
            check(Hd2dChars.ClassOf(21).Spec.Model == "Skeleton_Mage" && Hd2dChars.ClassOf(22).Spec.Model == "Skeleton_Warrior", "chars: the Lich and the Bone Lord are skeletons");
            check(Hd2dChars.ClassOf(17).Spec.Items.Length == 0 && Hd2dChars.ClassOf(17).Spec.Idle == "Unarmed_Idle", "chars: the Monk is unarmed and idles with bare hands");
            check(Hd2dChars.ClassOf(14).Spec.Idle == "2H_Melee_Idle" && Hd2dChars.ClassOf(4).Spec.Idle == "", "chars: a two-handed grip has its own idle clip");

            // every vocation id of the server's vocation files is a class
            string root = FindRoot();
            if (root != null)
            {
                var vocs = new HashSet<int>();
                foreach (var f in Directory.GetFiles(Path.Combine(root, "server", "data", "XML"), "chaos_vocations*.xml"))
                    foreach (Match m in Regex.Matches(File.ReadAllText(f), "<vocation id=\"(\\d+)\""))
                        vocs.Add(int.Parse(m.Groups[1].Value));
                check(vocs.Count == 21 && vocs.SetEquals(ids), "chars: the vocation ids of server/data/XML/chaos_vocations*.xml are the 21 classes (" + string.Join(",", vocs.OrderBy(x => x)) + ")");
            }

            // ---- which spec a creature gets
            check(Hd2dChars.SpecFor(Mk(1, 128), true, 0).Label == "Warrior" && Hd2dChars.SpecFor(Mk(9, 5), true, 0).Label == "Warrior", "chars: a player without a known vocation is the Warrior");
            check(Hd2dChars.SpecFor(Mk(1, 128), true, 21).Label == "Lich" && Hd2dChars.SpecFor(Mk(1, 128), true, 99).Label == "Warrior", "chars: the local player is its class from the login (an unknown id is the Warrior)");
            var other = Mk(2, 128); other.Vocation = 12;
            check(Hd2dChars.SpecFor(other, false, 4).Label == "Ninja", "chars: a creature with a known vocation is that class");
            var picks = Enumerable.Range(1, 400).Select(l => Hd2dChars.SpecFor(Mk(2, l), false, 0).Label).ToList();
            check(picks.Distinct().Count() >= 15, "chars: other players spread over the classes by look (" + picks.Distinct().Count() + " of 21 in 400 looks)");
            check(Hd2dChars.SpecFor(Mk(2, 130), false, 0).Label == Hd2dChars.SpecFor(Mk(77, 130), false, 0).Label, "chars: the same look gets the same class, whatever the id");
            check(Hd2dChars.SpecFor(Mk(5, 0), false, 0).Label == Hd2dChars.SpecFor(Mk(5, 0), false, 0).Label, "chars: look 0 picks by id, stable");
            var npcs = Enumerable.Range(1, 60).Select(l => Hd2dChars.SpecFor(Mk(3, l, type: 2), false, 0)).ToList();
            check(npcs.All(s => s.Label == "npc" && s.Items.Length == 0 && ValidSpec(s)) && npcs.Select(s => s.Model).Distinct().Count() == 4, "chars: NPCs are plain adventurers without weapons");
            check(Hd2dChars.SpecFor(Mk(4, 300, type: 1, name: "Risen Mage"), false, 0).Model == "Skeleton_Mage", "chars: a monster goes by its name");
            check(Hd2dChars.SpecFor(Mk(4, 300, type: 3, name: "Bone Golem"), false, 0).Model == "Skeleton_Warrior", "chars: a summon goes by its name");
            check(Hd2dChars.SpecFor(null, false, 0) != null, "chars: no creature, a default spec");
            check(Hd2dChars.Replaces(Mk(2, 129)) && !Hd2dChars.Replaces(Mk(2, 0)) && !Hd2dChars.Replaces(null), "chars: an outfit creature is replaced, an item look stays a sprite");

            // ---- monster rules on named examples
            Func<string, CharSpec> mon = n => Hd2dChars.MonsterSpec(n, 100);
            check(mon("Risen Skeleton").Model == "Skeleton_Minion" && mon("Risen Skeleton").Items.SequenceEqual(new[] { "Skeleton_Blade" }), "monster: a skeleton is the Skeleton_Minion with a blade");
            check(mon("Risen Warrior").Model == "Skeleton_Warrior" && mon("Bone Lancer").Model == "Skeleton_Warrior" && mon("Marrow Knight").Model == "Skeleton_Warrior", "monster: undead fighters are Skeleton_Warrior");
            check(mon("Bone Golem").Items.SequenceEqual(new[] { "Skeleton_Axe" }) && mon("Marrow Knight").Items.Contains("Skeleton_Shield_Large_A"), "monster: a golem swings an axe, a knight carries the large shield");
            check(mon("Risen Mage").Model == "Skeleton_Mage" && mon("Ice Lich").Model == "Skeleton_Mage" && mon("Death Mage").Model == "Skeleton_Mage" && mon("Lich Shade").Model == "Skeleton_Mage", "monster: liches and undead casters are Skeleton_Mage");
            check(mon("Risen Mage").Items.SequenceEqual(new[] { "Skeleton_Staff" }), "monster: a skeleton mage holds the staff");
            check(mon("Risen Archer").Model == "Skeleton_Rogue" && mon("Risen Archer").Items.SequenceEqual(new[] { "Skeleton_Crossbow" }), "monster: a risen archer is the Skeleton_Rogue with a crossbow");
            check(mon("Hollow Wraith").Model == "Skeleton_Rogue" && mon("Hollow Wraith").Items.Length == 0 && mon("Phantom Shade").Model == "Skeleton_Rogue" && mon("Count Varethil").Model == "Skeleton_Rogue", "monster: ghosts and vampires are the Skeleton_Rogue, ghosts with empty hands");
            check(mon("Sepulchre Ghoul").Model == "Skeleton_Minion" && mon("Rotten Corpse-grub").Model == "Skeleton_Minion", "monster: ghouls and grubs are the Skeleton_Minion");
            check(mon("Mercenary").Model == "Knight" && mon("Mercenary Ranger").Model == "Rogue" && mon("Mercenary Ranger").Items.SequenceEqual(new[] { "2H_Crossbow" }), "monster: humans are adventurers (a mercenary, a ranger)");
            check(mon("Hex Cultist").Model == "Mage" && mon("Hex Cultist").Items.Contains("Spellbook") && mon("Ward Barbarian").Model == "Barbarian" && mon("Goblin Warlock").Model == "Skeleton_Minion", "monster: cultists are Mage, barbarians Barbarian, goblins small skeletons");
            check(mon("Hex Cultist").Dim < Hd2dChars.Dim && mon("Mercenary").Dim < Hd2dChars.Dim, "monster: humans get a darker tint than the heroes");
            check(mon("Dire Bear").Model == "Skeleton_Warrior" && mon("Dire Bear").Items.Length == 0 && mon("Forest Wolf").Model == "Skeleton_Rogue" && mon("Glowcap Cluster").Model == "Skeleton_Mage", "monster: beasts are skeletons by build (heavy, fast, odd), with empty hands");
            check(mon("Zxqv").Model == "Skeleton_Minion" && mon("Zxqv").Label == "default" && mon("Zxqv").Items.Length == 0, "monster: everything else is the Skeleton_Minion, the default dark monster");
            check(mon("").Label == "unnamed" && ValidSpec(mon("")) && ValidSpec(Hd2dChars.MonsterSpec(null, 5)), "monster: no name, a skeleton by look");
            check(mon("Ice Dragon").B > mon("Ice Dragon").R && mon("Fire Man").R > mon("Fire Man").B && mon("Dire Bear").R == 1f, "monster: families tint the body (ice blue, fire orange), plain names stay neutral");
            check(Hd2dChars.Words("Ul'thazmor the Goblin-King").SequenceEqual(new[] { "ul", "thazmor", "the", "goblin", "king" }), "monster: words are letter runs");

            // ---- every monster name of the server: a model for each, and the share per model
            if (root != null)
            {
                var names = new List<(string name, int look, string src)>();
                foreach (var f in Directory.GetFiles(Path.Combine(root, "server", "data", "monster", "monsters"), "*.xml", SearchOption.AllDirectories))
                {
                    string text = File.ReadAllText(f);
                    var nm = Regex.Match(text, "<monster\\s[^>]*name=\"([^\"]+)\"");
                    var lk = Regex.Match(text, "<look\\s+type=\"(\\d+)\"");
                    if (nm.Success) names.Add((nm.Groups[1].Value, lk.Success ? int.Parse(lk.Groups[1].Value) : 0, "xml"));
                }
                int xmlCount = names.Count;
                string csv = Path.Combine(root, "server", "data", "monster", "base_monster_names.csv");
                if (File.Exists(csv))
                    foreach (var line in File.ReadAllLines(csv).Skip(1))
                    {
                        var p = line.Split(',');
                        if (p.Length >= 3 && p[2] == "monster") names.Add((p[1], 0, "base"));
                    }
                check(xmlCount >= 250, "monsters: the monster XML files were found (" + xmlCount + ")");
                int bad = 0;
                foreach (var n in names)
                {
                    var s = Hd2dChars.MonsterSpec(n.name, n.look);
                    if (!ValidSpec(s)) { bad++; Console.WriteLine("  no valid model for " + n.name + ": " + (s?.Model ?? "null")); }
                    float size = Hd2dChars.SizeFor(Mk(1, 100, type: 1, name: n.name), 1, 1);
                    if (size < Hd2dChars.MinSize || size > Hd2dChars.MaxSize) { bad++; Console.WriteLine("  size " + size + " for " + n.name); }
                }
                check(bad == 0, "monsters: all " + names.Count + " names have a valid model, fallback, items, tint and size");
                var share = names.GroupBy(n => Hd2dChars.MonsterSpec(n.name, n.look).Model).OrderByDescending(g => g.Count()).ToList();
                Console.WriteLine("monster models (" + names.Count + " names: " + xmlCount + " custom, " + (names.Count - xmlCount) + " base):");
                foreach (var g in share) Console.WriteLine("  " + g.Key.PadRight(18) + g.Count().ToString().PadLeft(4) + "  " + (100.0 * g.Count() / names.Count).ToString("0.0").PadLeft(5) + " %");
                var custom = names.Where(n => n.src == "xml").ToList();
                Console.WriteLine("  custom monsters only (" + custom.Count + "): " + string.Join(", ", custom.GroupBy(n => Hd2dChars.MonsterSpec(n.name, n.look).Model).OrderByDescending(g => g.Count()).Select(g => g.Key + " " + (100.0 * g.Count() / custom.Count).ToString("0.0") + " %")));
                var byRule = names.GroupBy(n => Hd2dChars.MonsterSpec(n.name, n.look).Label).OrderByDescending(g => g.Count());
                Console.WriteLine("monster rules: " + string.Join(", ", byRule.Select(g => g.Key + " " + g.Count())));
                check(share.Count >= 7, "monsters: at least 7 models are in use (" + share.Count + ")");
                check(share.All(g => g.Count() * 100.0 / names.Count <= 60.0), "monsters: no model takes over 60 % of the names");
                check(names.Count(n => Hd2dChars.MonsterSpec(n.name, n.look).Label == "default") * 100.0 / names.Count <= 50.0, "monsters: the default model is not most of them");
                var undeadWords = new[] { "skelet", "lich", "zombie", "ghoul", "ghost", "wraith", "necro", "mummy", "vampire", "crypt", "death" };
                check(names.Where(n => undeadWords.Any(w => n.name.ToLowerInvariant().Contains(w))).All(n => Hd2dChars.MonsterSpec(n.name, n.look).Model.StartsWith("Skeleton_", StringComparison.Ordinal)),
                    "monsters: every name with an undead keyword is a KayKit skeleton");
            }

            // ---- size
            Func<string, byte, Creature> mc = (n, t) => Mk(1, 100, type: t, name: n);
            check(Near(Hd2dChars.SizeFor(mc("Dire Bear", 1), 1, 1), 1f) && Near(Hd2dChars.SizeFor(mc("Hero", 0), 3, 3), 1f) && Near(Hd2dChars.SizeFor(mc("Bob", 2), 2, 2), 1f), "size: a standard monster is 1, players and NPCs always 1");
            check(Hd2dChars.SizeFor(mc("Dire Bear", 1), 2, 2) > 1.2f && Hd2dChars.SizeFor(mc("Dire Bear", 1), 3, 3) > Hd2dChars.SizeFor(mc("Dire Bear", 1), 2, 2), "size: bigger sprites are bigger");
            check(Near(Hd2dChars.SizeFor(mc("Dire Bear", 1), 5, 5), Hd2dChars.MaxSize) && Near(Hd2dChars.SizeFor(mc("Ancient Dragon", 1), 5, 5), Hd2dChars.MaxSize), "size: capped at 1.6");
            check(Hd2dChars.SizeFor(mc("Frost Lord", 1), 1, 1) > 1.1f && Hd2dChars.SizeFor(mc("Frost Whelp", 1), 1, 1) < 1f && Hd2dChars.SizeFor(mc("Frost Whelp", 1), 1, 1) >= Hd2dChars.MinSize, "size: big and small words in the name");

            // ---- hands and items
            check(Hd2dChars.IsWeaponNode("1H_Sword") && Hd2dChars.IsWeaponNode("Spellbook") && !Hd2dChars.IsWeaponNode("Knight_Body") && !Hd2dChars.IsWeaponNode("handslot.r"), "items: weapon nodes are told from body parts");
            check(Hd2dChars.WeaponNodes.All(n => Nodes.Values.Any(v => v.Contains(n))) && Hd2dChars.WeaponNodes.Length == Nodes.Values.SelectMany(v => v).Distinct().Count(), "items: the weapon node list is every node of the adventurer files");
            check(Hd2dChars.LeftHand("Round_Shield") && Hd2dChars.LeftHand("Knife_Offhand") && Hd2dChars.LeftHand("Spellbook") && Hd2dChars.LeftHand("Skeleton_Shield_Small_A") && !Hd2dChars.LeftHand("Skeleton_Blade") && !Hd2dChars.LeftHand("2H_Axe"), "items: shields, offhand blades and the spellbook go to the left hand");
            string[] bones = { "root", "hips", "handIK.r", "handIK.l", "wrist.r", "hand.r", "handslot.r", "hand.l", "handslot.l", "head" };
            check(Hd2dChars.HandBone(bones, true) == 6 && Hd2dChars.HandBone(bones, false) == 8, "hands: handslot.r and handslot.l, never an IK helper");
            check(Hd2dChars.HandBone(new[] { "Hand_R", "Hand_L", "handIK.r" }, true) == 0 && Hd2dChars.HandBone(new[] { "LeftHand", "RightHand" }, false) == 0 && Hd2dChars.HandBone(new[] { "RightHand", "LeftHand" }, true) == 0, "hands: a plain hand bone when there is no slot (Hand_R, RightHand)");
            check(Hd2dChars.HandBone(new[] { "head", "spine" }, true) == -1 && Hd2dChars.HandBone(new string[0], false) == -1 && Hd2dChars.HandBone(new[] { "handslot.l" }, true) == -1, "hands: no hand, no pick");
            check(Hd2dChars.KayKitTexture("Knight") == "knight_texture" && Hd2dChars.KayKitTexture("RogueHooded") == "rogue_texture" && Hd2dChars.KayKitTexture("Skeleton_Blade") == "skeleton_texture" && Hd2dChars.KayKitTexture("Skeleton_Mage") == "skeleton_texture"
                && Hd2dChars.KayKitTexture("Barbarian") == "barbarian_texture" && Hd2dChars.KayKitTexture("Mage") == "mage_texture", "items: the texture of each KayKit model");

            // ---- facing and place
            check(Near(Hd2dChars.Yaw(Dir.North), 0f) && Near(Hd2dChars.Yaw(Dir.East), 90f) && Near(Hd2dChars.Yaw(Dir.South), 180f) && Near(Hd2dChars.Yaw(Dir.West), 270f), "chars: north faces +z (away from the camera), then 90 degrees clockwise seen from above");
            check(Enum.GetValues(typeof(Dir)).Cast<Dir>().Select(Hd2dChars.Yaw).Distinct().Count() == 8, "chars: 8 facings, 8 yaws");
            var o = new Pos(100, 100, 7);
            check(Near(Hd2dChars.X(o, 100), 0.5f) && Near(Hd2dChars.Z(o, 100), -0.5f), "chars: the origin tile's centre");
            check(Near(Hd2dChars.X(o, 103), Hd2dRuins.TileX(o, 103)) && Near(Hd2dChars.Z(o, 98), Hd2dRuins.TileZ(o, 98)), "chars: same tile mapping as the ruins");
            check(Hd2dChars.Z(o, 98) > Hd2dChars.Z(o, 102), "chars: north (smaller y) is further from the camera (larger z)");
            check(Near(Hd2dChars.ScaleFor(2f) * 2f, Hd2dChars.Height) && Hd2dChars.Height >= 1.6f && Hd2dChars.Height <= 1.8f, "chars: scaled to 1.6-1.8 tiles");
            check(Near(Hd2dChars.ScaleFor(0f), 1f) && Near(Hd2dChars.ScaleFor(float.NaN), 1f), "chars: an unknown model height keeps scale 1");

            // ---- tint
            Hd2dChars.Tint(1f, 1f, 1f, out float tr, out float tg, out float tb);
            check(Near(tr, 0.75f) && Near(tg, 0.75f) && Near(tb, 0.75f), "chars: a white tint becomes 0.75 grey");
            Hd2dChars.Tint(1f, 0.2f, 0.2f, out tr, out tg, out tb);
            check(tr < 0.75f && tr > tg && (tr - tg) < (1f - 0.2f) * 0.75f, "chars: a red tint is dimmed and a little less saturated");
            Hd2dChars.Tint(1f, 1f, 1f, 0.95f, out tr, out tg, out tb);
            check(Near(tr, 0.95f) && Near(tb, 0.95f), "chars: a light tint dims less");
            Hd2dChars.Tint(5f, 5f, 5f, 1f, out tr, out tg, out tb);
            check(Near(tr, 1.5f), "chars: no channel over 1.5");
            Hd2dChars.Tint(Hd2dChars.ClassOf(23).Spec, out tr, out tg, out tb);
            Hd2dChars.Tint(Hd2dChars.ClassOf(8).Spec, out float jr, out float jg, out float jb);
            check(tr + tg + tb > jr + jg + jb, "chars: the holy Knight is lighter than the Juggernaut");

            // ---- idle clip
            string[] clips = { "__preview__x", "CharacterArmature|Death", "CharacterArmature|Idle_Attacking", "CharacterArmature|Idle_Weapon", "CharacterArmature|Idle", "CharacterArmature|Walk" };
            check(Hd2dChars.IdleClip(clips) == 4, "chars: plain Idle is the idle clip");
            check(Hd2dChars.IdleClip(new[] { "CharacterArmature|Idle_Attacking", "CharacterArmature|Idle_Weapon" }) == 1, "chars: Idle_Weapon beats Idle_Attacking");
            check(Hd2dChars.IdleClip(new[] { "CharacterArmature|Idle_Attacking", "Walk" }) == 0, "chars: any idle is better than none");
            check(Hd2dChars.IdleClip(new[] { "Walk", "Run" }) == -1 && Hd2dChars.IdleClip(new string[0]) == -1, "chars: no idle clip, no pick (bind pose)");
            string[] kay = { "T-Pose", "Spawn_Ground", "Jump_Idle", "2H_Melee_Idle", "Idle_Combat", "Idle", "Unarmed_Idle", "Walking_A" };
            check(Hd2dChars.IdleClip(kay) == 5, "chars: KayKit: Idle, not Idle_Combat or a jump idle");
            check(Hd2dChars.IdleClip(new[] { "T-Pose", "Idle_Combat", "Walking_A" }) == 1, "chars: KayKit: Idle_Combat when there is no Idle");
            check(Hd2dChars.IdleClip(kay, "2H_Melee_Idle") == 3 && Hd2dChars.IdleClip(kay, "unarmed_idle") == 6 && Hd2dChars.IdleClip(kay, "") == 5 && Hd2dChars.IdleClip(kay, "Nope") == 5, "chars: a preferred idle clip when the model has it, else the plain idle");
            float t = Hd2dChars.IdleTime(5, 2f);
            check(t >= 0f && t < 2f && Near(t, Hd2dChars.IdleTime(5, 2f)) && Near(Hd2dChars.IdleTime(5, 0f), 0f), "chars: the idle sample time is inside the clip and stable");

            check(Hd2dChars.TextureFor("Warrior", "Warrior_Texture") == "Warrior_Texture", "chars: body material binds the body texture");
            check(Hd2dChars.TextureFor("Warrior", "Warrior_Sword_Texture (Instance)") == "Warrior_Sword_Texture", "chars: the weapon material binds the weapon texture");
            check(Hd2dChars.TextureFor("Cleric", "Cleric_Staff") == "Cleric_Staff_Texture" && Hd2dChars.TextureFor("Cleric", "Material") == "Cleric_Texture", "chars: other names fall back to the body texture");

            // ---- the pixel font of the labels
            check(PixelText.Has('a') && PixelText.Has('Z') && PixelText.Has('7') && PixelText.Has(' ') && PixelText.Has('-') && !PixelText.Has('#'), "text: the font has letters of both cases, digits, space and dash");
            var mk = PixelText.Mask("Hi", 2, out int tw, out int th);
            check(tw == PixelText.Width("Hi", 2) && tw == (2 * 6 - 1) * 2 && th == 14 && mk.Length == tw * th && mk.Count(x => x) > 20, "text: mask size and ink");
            check(PixelText.Mask("hi", 2, out _, out _).SequenceEqual(mk), "text: lower case draws as upper case");
            var blank = PixelText.Mask("# ", 1, out int bw, out int bh);
            check(bw == 11 && bh == 7 && blank.All(x => !x), "text: an unknown character and a space are blank");
            check(PixelText.Mask("", 3, out int ew, out int eh).Length == 0 && ew == 0 && eh == 21, "text: an empty text has no pixels");
            var ink = new HashSet<string>();
            foreach (char ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
                ink.Add(string.Concat(PixelText.Mask(ch.ToString(), 1, out _, out _).Select(x => x ? '1' : '0')));
            check(ink.Count == 36, "text: every letter and digit has its own glyph");
            var all = Hd2dChars.Classes.Select(c => c.Name).Concat(Hd2dDemo.Cast.Select(c => c.Name));
            check(all.All(n => n.All(PixelText.Has)), "text: every class name and cast name can be drawn");

            // ---- the line-up of the cast screenshot
            var room = Hd2dDemo.Synthetic();
            int before = room.World.Creatures.Count;
            var cast = room.Lineup();
            check(before == 2 && cast.Count == Hd2dDemo.Cast.Length && room.World.Creatures.Count == cast.Count, "cast: the room's two creatures are replaced by the cast of " + cast.Count);
            var spots = cast.Select(c => c.Position.X + "," + c.Position.Y).ToList();
            check(spots.Distinct().Count() == cast.Count, "cast: one tile each");
            check(cast.All(c => Math.Abs(c.Position.X - room.Center.X) <= 8 && c.Position.Y >= room.Center.Y - 4 && c.Position.Y <= room.Center.Y + 7 && c.Position.Z == room.Center.Z), "cast: everybody stands on the room's floor");
            int onTiles = room.World.Tiles.Values.Sum(t2 => t2.Things.Count(th2 => th2.IsCreature));
            check(onTiles == cast.Count, "cast: each creature is on a tile once, no creature of the old room is left");
            var specs = cast.Select(c => Hd2dChars.SpecFor(c, false, 0)).ToList();
            check(specs.All(ValidSpec), "cast: every member has a valid spec");
            check(specs.Select(s => s.Model).Distinct().Count() >= 7, "cast: the line-up shows at least 7 models (" + string.Join(",", specs.Select(s => s.Model).Distinct()) + ")");
            check(specs.Skip(0).Take(4).Select(s => s.Model).OrderBy(x => x).SequenceEqual(new[] { "Skeleton_Minion", "Skeleton_Mage", "Skeleton_Rogue", "Skeleton_Warrior" }.OrderBy(x => x)), "cast: the back row is the four dark skeletons");
            check(specs.Skip(4).Select(s => s.Label).SequenceEqual(new[] { "Juggernaut", "Deadeye", "Elementalist", "Ninja", "Lich", "Shadowfist", "Inquisitor" }), "cast: the front row is seven classes, one per group");
            check(cast.All(c => Hd2dChars.Replaces(c) && c.Direction == Dir.South) && room.Lineup().Count == cast.Count, "cast: all are drawn as models, face the camera, and the line-up can be made again");
            check(room.World.Creatures.ContainsKey(room.World.PlayerId), "cast: the player id is one of the cast");
        }
    }
}
