// Import settings of the 3D characters (Resources/Chars3d and Resources/KayKit): the repo commits no .meta files, so the importer would
// use its defaults. This sets them in code: a Generic rig, the animations from the file, the bones kept as objects (SampleAnimation binds
// by path), no cameras or lights. The KayKit files (fetched by unity/tools/fetch_3d_assets.py) are about 20 MB each with about 90
// takes; only the characters keep their animations, the weapon FBX files (Skeleton_Blade, ...) are plain meshes.
// Textures are bound at runtime by Unity/Hd2dChars3d.cs, not here. Editor only (Client.Check skips it).
using System;
using System.IO;
using UnityEditor;

namespace Chaos.Client.Editor
{
    public sealed class Chars3dImport : AssetPostprocessor
    {
        static readonly string[] KayCharacters =
        {
            "Knight", "Barbarian", "Mage", "Rogue", "RogueHooded", "Skeleton_Warrior", "Skeleton_Mage", "Skeleton_Rogue", "Skeleton_Minion",
        };

        void OnPreprocessModel()
        {
            string path = assetPath.Replace('\\', '/');
            bool chars = path.Contains("/Resources/Chars3d/");
            bool kay = path.Contains("/Resources/KayKit/");
            if (!chars && !kay) return;
            var m = (ModelImporter)assetImporter;
            m.animationType = ModelImporterAnimationType.Generic;
            m.importAnimation = chars || Array.IndexOf(KayCharacters, Path.GetFileNameWithoutExtension(path)) >= 0;
            m.optimizeGameObjects = false;
            m.importCameras = false;
            m.importLights = false;
            m.importBlendShapes = false;
            m.materialImportMode = ModelImporterMaterialImportMode.ImportStandard;
        }
    }
}
