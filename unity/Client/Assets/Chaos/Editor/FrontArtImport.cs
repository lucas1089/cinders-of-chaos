// Import settings of the front-art characters (Resources/FrontArt): the repo commits no .meta files, so the importer would use its
// defaults, which compress the pictures (blocky pixels) and mip them. This keeps them as drawn: uncompressed, point filtered, no mips,
// clamped, readable, transparency kept. Editor only (Client.Check skips it).
using UnityEditor;

namespace Chaos.Client.Editor
{
    public sealed class FrontArtImport : AssetPostprocessor
    {
        void OnPreprocessTexture()
        {
            string path = assetPath.Replace('\\', '/');
            if (!path.Contains("/Resources/FrontArt/")) return;
            var t = (TextureImporter)assetImporter;
            t.textureType = TextureImporterType.Default;
            t.textureCompression = TextureImporterCompression.Uncompressed;
            t.filterMode = UnityEngine.FilterMode.Point;
            t.mipmapEnabled = false;
            t.wrapMode = UnityEngine.TextureWrapMode.Clamp;
            t.alphaIsTransparency = true;
            t.npotScale = TextureImporterNPOTScale.None;
            t.isReadable = true;
            if (path.EndsWith("_n.png"))
            {
                // a normal map (PixelLab, OpenGL convention): linear, its alpha is coverage, not transparency to bleed
                t.sRGBTexture = false;
                t.alphaIsTransparency = false;
            }
        }
    }
}
