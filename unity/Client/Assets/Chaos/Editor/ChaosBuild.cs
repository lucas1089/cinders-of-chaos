// Batch build of the prototype (unity/README.md, .github/workflows/unity-prototype.yml):
//   Unity -batchmode -quit -projectPath unity/Client -executeMethod Chaos.Client.Editor.ChaosBuild.Build
//         -buildTarget StandaloneWindows64|StandaloneLinux64|Android -customBuildPath OUT
// The scene is made here (one empty scene; ChaosApp builds everything from code at start).
// The client guard key goes into the build only when CHAOS_EMBED_CLIENT_KEY=1 and CHAOS_CLIENT_KEY is set (or a CI step
// wrote Generated/Resources/chaos_client_key.txt on the owner's opt-in); the file is deleted after the build and is
// git-ignored (Assets/Chaos/Generated).
using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace Chaos.Client.Editor
{
    public static class ChaosBuild
    {
        const string Generated = "Assets/Chaos/Generated";
        const string ScenePath = Generated + "/Main.unity";
        const string KeyPath = Generated + "/Resources/chaos_client_key.txt";
        const string RsaPath = Generated + "/Resources/chaos_rsa.txt";      // public: the server's RSA modulus
        const string BuildPath = Generated + "/Resources/chaos_build.txt";  // the client build the guard expects
        const string LogoPath = Generated + "/Resources/chaos_logo.png";    // docs/brand: splash screen and login header
        const string IconPath = Generated + "/chaos_icon.png";

        static string Arg(string name, string fallback)
        {
            var args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++)
                if (args[i] == name) return args[i + 1];
            return fallback;
        }

        static void WriteIfSet(string path, string value)
        {
            if (!string.IsNullOrWhiteSpace(value)) File.WriteAllText(path, value.Trim());
        }

        /// <summary>Copies a docs/brand file into the project (the repo root is two levels above the project).</summary>
        static void CopyBrand(string name, string to)
        {
            string from = Path.GetFullPath(Path.Combine(Application.dataPath, "../../../docs/brand", name));
            if (File.Exists(from)) File.Copy(from, to, true);
            else Debug.LogWarning("chaos build: no " + from + "; the splash screen keeps its default");
        }

        static Sprite ImportSprite(string path)
        {
            if (!(AssetImporter.GetAtPath(path) is TextureImporter imp)) return null;
            imp.textureType = TextureImporterType.Sprite;
            imp.spriteImportMode = SpriteImportMode.Single;
            imp.alphaIsTransparency = true;
            imp.mipmapEnabled = false;
            imp.isReadable = true;   // the login screen reads it from Resources too
            imp.SaveAndReimport();
            return AssetDatabase.LoadAssetAtPath<Sprite>(path);
        }

        public static void Build()
        {
            Directory.CreateDirectory(Generated + "/Resources");
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorSceneManager.SaveScene(scene, ScenePath);

            string key = Environment.GetEnvironmentVariable("CHAOS_CLIENT_KEY");
            bool embed = Environment.GetEnvironmentVariable("CHAOS_EMBED_CLIENT_KEY") == "1" && !string.IsNullOrEmpty(key);
            // files a CI step wrote before the build (the container may not pass the environment on) stay as they are
            if (embed) File.WriteAllText(KeyPath, key.Trim());
            WriteIfSet(RsaPath, Environment.GetEnvironmentVariable("CHAOS_RSA_PUBLIC"));
            WriteIfSet(BuildPath, Environment.GetEnvironmentVariable("CHAOS_CLIENT_BUILD"));
            embed = File.Exists(KeyPath);
            CopyBrand("cinders_logo.png", LogoPath);
            CopyBrand("cinders_logo_icon.png", IconPath);
            AssetDatabase.Refresh();
            var logo = ImportSprite(LogoPath);
            var icon = AssetDatabase.LoadAssetAtPath<Texture2D>(IconPath);

            var target = EditorUserBuildSettings.activeBuildTarget;
            string outPath = Arg("-customBuildPath", "Builds/" + target);
            if (target == BuildTarget.StandaloneWindows64 && !outPath.EndsWith(".exe")) outPath = Path.Combine(outPath, "ChaosUnity.exe");
            if (target == BuildTarget.StandaloneLinux64 && !outPath.EndsWith(".x86_64")) outPath = Path.Combine(outPath, "ChaosUnity.x86_64");
            if (target == BuildTarget.Android && !outPath.EndsWith(".apk")) outPath = Path.Combine(outPath, "ChaosUnity.apk");

            PlayerSettings.companyName = "Cinders of Chaos";
            PlayerSettings.productName = "Cinders of Chaos (Unity prototype)";
            PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.Android, "com.cindersofchaos.unityprototype");
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel24;
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            PlayerSettings.SetScriptingBackend(BuildTargetGroup.Android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.forceInternetPermission = true;
            PlayerSettings.defaultScreenWidth = 1280;
            PlayerSettings.defaultScreenHeight = 720;
            PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
            PlayerSettings.resizableWindow = true;
            if (icon != null) PlayerSettings.SetIcons(NamedBuildTarget.Unknown, new[] { icon }, IconKind.Any);

            // splash screen: our logo on the game's dark background. A Personal license keeps the engine's
            // "Made with" line under it; showUnityLogo = false takes effect only on a license that allows it.
            PlayerSettings.SplashScreen.show = true;
            PlayerSettings.SplashScreen.showUnityLogo = false;
            PlayerSettings.SplashScreen.drawMode = PlayerSettings.SplashScreen.DrawMode.UnityLogoBelow;
            PlayerSettings.SplashScreen.unityLogoStyle = PlayerSettings.SplashScreen.UnityLogoStyle.LightOnDark;
            PlayerSettings.SplashScreen.animationMode = PlayerSettings.SplashScreen.AnimationMode.Dolly;
            PlayerSettings.SplashScreen.backgroundColor = new Color32(6, 5, 8, 255);
            PlayerSettings.SplashScreen.overlayOpacity = 0f;
            PlayerSettings.SplashScreen.logos = logo != null
                ? new[] { PlayerSettings.SplashScreenLogo.Create(2.5f, logo) }
                : new PlayerSettings.SplashScreenLogo[0];

            var options = new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = outPath,
                target = target,
                options = BuildOptions.None,
            };
            BuildReport report = BuildPipeline.BuildPlayer(options);
            if (File.Exists(KeyPath)) { File.Delete(KeyPath); AssetDatabase.Refresh(); }
            Debug.Log("chaos build: " + report.summary.result + ", " + report.summary.totalSize + " bytes, " + outPath +
                      (embed ? " (client key embedded)" : " (development guard key)"));
            if (report.summary.result != BuildResult.Succeeded)
            {
                EditorApplication.Exit(1);
            }
        }
    }
}
