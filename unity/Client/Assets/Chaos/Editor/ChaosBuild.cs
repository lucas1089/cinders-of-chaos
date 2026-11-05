// Batch build of the prototype (unity/README.md, .github/workflows/unity-prototype.yml):
//   Unity -batchmode -quit -projectPath unity/Client -executeMethod Chaos.Client.Editor.ChaosBuild.Build
//         -buildTarget StandaloneWindows64|StandaloneLinux64|Android -customBuildPath OUT
// The scene is made here (one empty scene; ChaosApp builds everything from code at start).
// The client guard key goes into the build only when CHAOS_EMBED_CLIENT_KEY=1 and CHAOS_CLIENT_KEY is set; the file
// is deleted again after the build and is git-ignored (Assets/Chaos/Generated).
using System;
using System.IO;
using UnityEditor;
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

        static string Arg(string name, string fallback)
        {
            var args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++)
                if (args[i] == name) return args[i + 1];
            return fallback;
        }

        public static void Build()
        {
            Directory.CreateDirectory(Generated + "/Resources");
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorSceneManager.SaveScene(scene, ScenePath);

            string key = Environment.GetEnvironmentVariable("CHAOS_CLIENT_KEY");
            bool embed = Environment.GetEnvironmentVariable("CHAOS_EMBED_CLIENT_KEY") == "1" && !string.IsNullOrEmpty(key);
            if (embed) File.WriteAllText(KeyPath, key.Trim());
            else if (File.Exists(KeyPath)) File.Delete(KeyPath);
            AssetDatabase.Refresh();

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
