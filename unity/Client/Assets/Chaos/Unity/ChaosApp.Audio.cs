// Game sounds and region music (phase 5, track R): plays the cues of VisualEffects (Core/GameVisual.cs, rules in Core/Audio.cs) and cross-fades the music
// of the region the player is in. The files are the main client's own, game_chaossound/sounds/*.ogg and game_chaosmusic/music/*.ogg: they are read from the
// first overlay folder that has them (OverlayFiles: CHAOS_OVERLAY_DIR, StreamingAssets/overlay/modules, beside the executable, the repository's
// client/overlay/modules), so no audio is committed to the Unity project. Without the files the game is silent and says so once in the log.
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Networking;

namespace Chaos.Client
{
    /// <summary>The options of this track, loaded from PlayerPrefs once and shared with the session's models.</summary>
    public static class VisualPrefs
    {
        public static SoundSettings Sound = new SoundSettings();
        public static MusicSettings Music = new MusicSettings();
        public static LootBeamSettings Beams = new LootBeamSettings();
        public static VisualFxOptions Fx = new VisualFxOptions();
        public static int EffectPercent = EffectOpacity.Default;
        public static bool Decals = true, ChestAuras = true, ErrorColorOn = true, UiFadeOn = true, LayoutOn = true;
        public static bool WingsOwn = true, WingsOthers = true, PrintsOthers = true, GlowsOthers = true;
        /// <summary>The rarity outline of items on the map (phase 7 track Y, MapItemOutline).</summary>
        public static bool ItemOutlines = true;
        /// <summary>The health and mana globes beside the hotkey bar (track U; drawn only when the orb pictures are found).</summary>
        public static bool Globes = true, WideView = true;
        public const string GlobesPref = "chaos.globes";
        public static int ViewRows = ViewZoom.DefaultRows;
        /// <summary>The character in the game now (set by ChaosApp), whose zoom is kept.</summary>
        public static string CurrentCharacter;
        static bool loaded;

        static bool Flag(string key, bool def) => PlayerPrefs.GetInt(key, def ? 1 : 0) == 1;
        static void SetFlag(string key, bool on) { PlayerPrefs.SetInt(key, on ? 1 : 0); }

        public static void Load()
        {
            if (loaded) return;
            loaded = true;
            Sound = SoundSettings.From(Json.TryParse(PlayerPrefs.GetString(SoundSettings.Pref, "")));
            Music = MusicSettings.From(Json.TryParse(PlayerPrefs.GetString(MusicSettings.Pref, "")));
            Beams = LootBeamSettings.From(Json.TryParse(PlayerPrefs.GetString(LootBeamSettings.Pref, "")));
            Fx = VisualFxOptions.From(Json.TryParse(PlayerPrefs.GetString(VisualFxOptions.Pref, "")));
            EffectPercent = EffectOpacity.Clamp(PlayerPrefs.GetInt(EffectOpacity.Pref, EffectOpacity.Default));
            Decals = Flag(CombatDecals.Pref, true); ChestAuras = Flag(ChestAuraState.Pref, true);
            ErrorColorOn = Flag(ErrorColor.Pref, true); UiFadeOn = Flag(UiFade.Pref, true); LayoutOn = Flag(WindowLayout.Pref + "on", true);
            WingsOwn = Flag(LevelWingsState.OwnPref, true); WingsOthers = Flag(LevelWingsState.OthersPref, true);
            PrintsOthers = Flag(CosmeticFxState.OthersPrintsPref, true); GlowsOthers = Flag(CosmeticFxState.OthersGlowPref, true);
            ViewRows = ViewZoom.Clamp(PlayerPrefs.GetInt(ViewZoom.Pref, ViewZoom.DefaultRows), ViewZoom.HardMaxRows);
            WideView = Flag(ViewZoom.WidePref, true);
            Globes = Flag(GlobesPref, true);
            ItemOutlines = Flag(MapItemOutline.PrefKey, true);
            ErrorColor.Enabled = ErrorColorOn;
        }

        public static void Save()
        {
            PlayerPrefs.SetString(SoundSettings.Pref, Sound.ToJson());
            PlayerPrefs.SetString(MusicSettings.Pref, Music.ToJson());
            PlayerPrefs.SetString(LootBeamSettings.Pref, Beams.ToJson());
            PlayerPrefs.SetString(VisualFxOptions.Pref, Fx.ToJson());
            PlayerPrefs.SetInt(EffectOpacity.Pref, EffectPercent);
            SetFlag(CombatDecals.Pref, Decals); SetFlag(ChestAuraState.Pref, ChestAuras); SetFlag(ErrorColor.Pref, ErrorColorOn);
            SetFlag(UiFade.Pref, UiFadeOn); SetFlag(WindowLayout.Pref + "on", LayoutOn);
            SetFlag(LevelWingsState.OwnPref, WingsOwn); SetFlag(LevelWingsState.OthersPref, WingsOthers);
            SetFlag(CosmeticFxState.OthersPrintsPref, PrintsOthers); SetFlag(CosmeticFxState.OthersGlowPref, GlowsOthers);
            PlayerPrefs.SetInt(ViewZoom.Pref, ViewRows);
            SetFlag(ViewZoom.WidePref, WideView);
            if (ViewZoom.CharKey(CurrentCharacter) is string ck) PlayerPrefs.SetInt(ck, ViewRows);
            SetFlag(GlobesPref, Globes);
            SetFlag(MapItemOutline.PrefKey, ItemOutlines);
            ErrorColor.Enabled = ErrorColorOn;
            PlayerPrefs.Save();
        }

        /// <summary>Gives a session's models the saved options (the objects are shared, so a change shows at once).</summary>
        public static void Apply(VisualEffects v)
        {
            v.Sound = Sound; v.Music = Music; v.Beams = Beams; v.Fx = Fx; v.DecalsOn = Decals;
            v.Aura.Enabled = ChestAuras; v.Wings.Own = WingsOwn; v.Wings.Others = WingsOthers;
            v.Cosmetic.OthersPrints = PrintsOthers; v.Cosmetic.OthersOutlines = GlowsOthers;
        }
    }

    public sealed partial class ChaosApp
    {
        const int SfxVoices = 8;
        AudioSource[] sfxVoices;
        AudioSource musicA, musicB;
        string musicRegionA, musicRegionB;
        double musicFadeStart;
        bool musicFading;
        readonly Dictionary<string, AudioClip> clips = new Dictionary<string, AudioClip>();
        readonly HashSet<string> clipsLoading = new HashSet<string>(), clipsMissing = new HashSet<string>();
        List<string> overlayRoots;
        bool audioPreloaded, audioWarned;
        string musicWant;

        /// <summary>The folders that may hold the main client's modules (cached).</summary>
        List<string> OverlayRoots()
        {
            if (overlayRoots != null) return overlayRoots;
            string exe = Path.GetDirectoryName(Application.dataPath) ?? ".";
            overlayRoots = OverlayFiles.Candidates(Environment.GetEnvironmentVariable(OverlayFiles.EnvVar), Application.streamingAssetsPath, exe, exe);
            return overlayRoots;
        }

        /// <summary>The full path of a file of the main client's modules, null when no folder has it.</summary>
        public string OverlayPath(string rel) => OverlayFiles.Find(OverlayRoots(), rel, File.Exists);

        void AudioSetup()
        {
            if (sfxVoices != null) return;
            sfxVoices = new AudioSource[SfxVoices];
            for (int i = 0; i < SfxVoices; i++)
            {
                var a = gameObject.AddComponent<AudioSource>();
                a.playOnAwake = false; a.spatialBlend = 0f;
                sfxVoices[i] = a;
            }
            musicA = gameObject.AddComponent<AudioSource>(); musicB = gameObject.AddComponent<AudioSource>();
            foreach (var m in new[] { musicA, musicB }) { m.playOnAwake = false; m.loop = true; m.spatialBlend = 0f; m.volume = 0f; }
        }

        /// <summary>Loads a clip of the overlay into the cache (once); done is called when it is there (or missing).</summary>
        void LoadClip(string rel, Action<AudioClip> done)
        {
            if (clips.TryGetValue(rel, out var c)) { done?.Invoke(c); return; }
            if (clipsMissing.Contains(rel)) { done?.Invoke(null); return; }
            if (!clipsLoading.Add(rel)) return;
            string path = OverlayPath(rel);
            if (path == null)
            {
                clipsMissing.Add(rel); clipsLoading.Remove(rel);
                if (!audioWarned) { audioWarned = true; Debug.Log("chaos audio: no " + rel + " in " + string.Join(", ", OverlayRoots()) + " (set " + OverlayFiles.EnvVar + ")"); }
                done?.Invoke(null);
                return;
            }
            StartCoroutine(ReadClip(rel, path, done));
        }

        IEnumerator ReadClip(string rel, string path, Action<AudioClip> done)
        {
            string url = "file://" + path.Replace('\\', '/');
            using (var req = UnityWebRequestMultimedia.GetAudioClip(url, AudioType.OGGVORBIS))
            {
                yield return req.SendWebRequest();
                AudioClip clip = null;
                if (req.result == UnityWebRequest.Result.Success) { clip = DownloadHandlerAudioClip.GetContent(req); if (clip != null) clip.name = rel; }
                clipsLoading.Remove(rel);
                if (clip != null) clips[rel] = clip; else clipsMissing.Add(rel);
                done?.Invoke(clip);
            }
        }

        IEnumerator PreloadSounds()
        {
            foreach (string f in SoundLogic.AllFiles())
            {
                string rel = SoundLogic.Dir + f + ".ogg";
                if (clips.ContainsKey(rel) || clipsMissing.Contains(rel)) continue;
                bool done = false;
                LoadClip(rel, _ => done = true);
                while (!done) yield return null;
            }
        }

        /// <summary>Plays the cues the session queued and runs the music. Called every frame from VisualUpdate.</summary>
        void AudioUpdate(VisualEffects v)
        {
            AudioSetup();
            if (!audioPreloaded) { audioPreloaded = true; StartCoroutine(PreloadSounds()); }
            float master = AudioListener.volume;
            if (v != null)
                while (v.DequeueCue(out var pick))
                {
                    string rel = SoundLogic.Dir + pick.File + ".ogg";
                    if (!clips.TryGetValue(rel, out var clip)) { LoadClip(rel, null); continue; }   // plays from the next cue on
                    var voice = FreeVoice();
                    if (voice == null) continue;
                    voice.clip = clip; voice.volume = Mathf.Clamp01(pick.Gain); voice.Play();
                }
            RuleSoundUpdate();
            MusicUpdate(v);
        }

        /// <summary>Plays the loot filter's rule sound of a kill (phase 7 track Y; the file is the main client's own game_lootfilter/sounds/*.ogg).</summary>
        void RuleSoundUpdate()
        {
            var f = FindWindow<LootWindow>()?.Filter;
            if (f == null || !f.SoundPending) return;
            f.SoundPending = false;
            PlayRuleFile(f.SoundFile, f.SoundGain);
        }

        void PlayRuleFile(string rel, float gain)
        {
            if (string.IsNullOrEmpty(rel)) return;
            LoadClip(rel, clip =>
            {
                var voice = FreeVoice();
                if (clip == null || voice == null) return;
                voice.clip = clip; voice.volume = Mathf.Clamp01(gain); voice.Play();
            });
        }

        /// <summary>The play button of the Rules tab: a sound id (1 .. 5) at the volume (0 .. 100).</summary>
        public void PlayRuleSound(int id, int volume)
        {
            PlayRuleFile(LootRuleSounds.File(id), Mathf.Clamp01(volume / 100f));
        }

        AudioSource FreeVoice()
        {
            foreach (var a in sfxVoices) if (!a.isPlaying) return a;
            return null;
        }

        /// <summary>Plays one cue by event key from the options page (a test sound), outside the mixer's gaps.</summary>
        public void PlayTestSound(string key)
        {
            if (!SoundLogic.Sets.TryGetValue(key, out var set)) return;
            string rel = SoundLogic.Dir + set.Files[0] + ".ogg";
            LoadClip(rel, clip =>
            {
                var voice = FreeVoice();
                if (clip == null || voice == null) return;
                voice.clip = clip; voice.volume = Mathf.Clamp01(set.Gain * SoundLogic.Volumes[VisualPrefs.Sound.Volume]); voice.Play();
            });
        }

        void MusicUpdate(VisualEffects v)
        {
            var st = VisualPrefs.Music;
            string region = screen == Screen.Game && v != null ? v.Region : "login";
            string rel = MusicLogic.File(region);
            bool haveFile = rel != null && OverlayPath(rel) != null;
            string silent = MusicLogic.SilentReason(st, true, Application.isFocused, haveFile);
            float gain = silent == null ? st.Gain : 0f;
            double now = Time.unscaledTimeAsDouble;
            if (region != musicWant)
            {
                musicWant = region;
                if (rel != null) LoadClip(rel, clip => { if (clip != null && musicWant == region) StartTrack(region, clip, now); });
            }
            // the volumes: the current track follows the gain, the old one fades out over the cross-fade
            float fadeIn = 1f, fadeOut = 0f;
            if (musicFading)
            {
                MusicLogic.Fade(now - musicFadeStart, MusicLogic.Crossfade, out fadeOut, out fadeIn);
                if (fadeIn >= 1f) { musicFading = false; musicB.Stop(); musicB.volume = 0f; musicRegionB = null; }
            }
            // a lerp toward the target keeps a mute from clicking
            float k = 1f - Mathf.Exp(-Time.unscaledDeltaTime / (silent != null ? (float)MusicLogic.MuteFade / 4f : 0.25f));
            musicA.volume = Mathf.Lerp(musicA.volume, gain * fadeIn, k);
            if (musicFading) musicB.volume = Mathf.Lerp(musicB.volume, gain * fadeOut, k);
            if (silent == "off" && musicA.isPlaying && musicA.volume < 0.001f) musicA.Pause();
            else if (silent == null && musicA.clip != null && !musicA.isPlaying) musicA.UnPause();
        }

        void StartTrack(string region, AudioClip clip, double now)
        {
            if (musicRegionA == region && musicA.clip == clip && musicA.isPlaying) return;
            if (musicA.isPlaying)
            {
                // the old track moves to B and fades out while A takes the new one
                musicB.clip = musicA.clip; musicB.time = musicA.time; musicB.volume = musicA.volume; musicB.Play();
                musicRegionB = musicRegionA;
                musicFading = true; musicFadeStart = now;
            }
            musicA.clip = clip; musicA.volume = 0f; musicA.time = 0f; musicA.Play();
            musicRegionA = region;
        }

        /// <summary>The region now playing (for the options page).</summary>
        public string MusicRegionPlaying => musicRegionA ?? "";
    }
}
