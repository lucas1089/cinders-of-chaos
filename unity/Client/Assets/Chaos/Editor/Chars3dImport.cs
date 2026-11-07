// Import settings of the 3D characters (Resources/Chars3d): the repo commits no .meta files, so the importer would use its defaults.
// This sets them in code: a Generic rig, the animations from the file, the bones kept as objects (SampleAnimation binds by path),
// no cameras or lights. Textures are bound at runtime by Unity/Hd2dChars3d.cs, not here. Editor only (Client.Check skips it).
using UnityEditor;

namespace Chaos.Client.Editor
{
    public sealed class Chars3dImport : AssetPostprocessor
    {
        void OnPreprocessModel()
        {
            if (!assetPath.Replace('\\', '/').Contains("/Resources/Chars3d/")) return;
            var m = (ModelImporter)assetImporter;
            m.animationType = ModelImporterAnimationType.Generic;
            m.importAnimation = true;
            m.optimizeGameObjects = false;
            m.importCameras = false;
            m.importLights = false;
            m.materialImportMode = ModelImporterMaterialImportMode.ImportStandard;
        }
    }
}
