// Community glue of the app (O433 phase 5, track S): the windows (Windows/CommunityWindows.cs), the hooks of the panels into the app (clipboard, saved options, the files of a
// performance record, the screenshots), streamer and cinema mode (Ctrl+Shift+S, Ctrl+Shift+H), the performance sample per frame, the card borders of deck bags (ContainersWindow).
using System;
using System.Collections.Generic;
using System.IO;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        StreamerState streamerState;

        /// <summary>Streamer mode: made on first use (the character list needs it before a session exists), options in PlayerPrefs.</summary>
        StreamerState streamer
        {
            get
            {
                if (streamerState == null)
                {
                    streamerState = new StreamerState
                    {
                        Load = k => { try { return PlayerPrefs.GetInt("chaos." + k, 0) == 1; } catch { return false; } },
                        Save = (k, v) => { try { PlayerPrefs.SetInt("chaos." + k, v ? 1 : 0); } catch { } },
                    };
                    streamerState.LoadAll();
                }
                return streamerState;
            }
        }

        /// <summary>The community windows, added by MakeWindows.</summary>
        void AddCommunityWindows()
        {
            windows.Add(new AdminWindow()); windows.Add(new BossSpawnsWindow()); windows.Add(new SurveyWindow()); windows.Add(new NemesisWindow());
            windows.Add(new ReferralWindow()); windows.Add(new CommunityGoalWindow()); windows.Add(new ChronicleWindow()); windows.Add(new MentorWindow());
            windows.Add(new PatchNotesWindow()); windows.Add(new DropFeedWindow()); windows.Add(new CreditsWindow()); windows.Add(new StreamerWindow());
            windows.Add(new PerfWindow()); windows.Add(new ShotsWindow()); windows.Add(new OutfitExtrasWindow());
        }

        static string DataDir() { try { return Application.persistentDataPath; } catch { return "."; } }

        static bool Pref(string key, bool fallback) { try { return PlayerPrefs.GetInt(key, fallback ? 1 : 0) == 1; } catch { return fallback; } }

        /// <summary>Called when a character enters the game: the panels' callbacks into the app.</summary>
        void CommunityEntered()
        {
            var c = session.Community;
            c.Referral.Copy = text => { try { GUIUtility.systemCopyBuffer = text; } catch { } };
            c.PatchNotes.DailyVisible = () => FindWindow<DailyWindow>()?.Open == true;
            c.PatchNotes.LoadSeen = () => { try { return PlayerPrefs.GetFloat("chaos.patchnotes.seen", 0f); } catch { return 0; } };
            c.PatchNotes.SaveSeen = v => { try { PlayerPrefs.SetFloat("chaos.patchnotes.seen", (float)v); } catch { } };
            c.DropFeed.Load = () => { try { return PlayerPrefs.GetString("chaos.dropfeed", ""); } catch { return ""; } };
            c.DropFeed.Save = m => { try { PlayerPrefs.SetString("chaos.dropfeed", m); } catch { } };
            c.Shots.Load = k => { try { return PlayerPrefs.HasKey("chaos." + k) ? PlayerPrefs.GetInt("chaos." + k) == 1 : (bool?)null; } catch { return null; } };
            c.Shots.Save = (k, v) => { try { PlayerPrefs.SetInt("chaos." + k, v ? 1 : 0); } catch { } };
            c.Shots.Exists = p => File.Exists(Path.Combine(DataDir(), p));
            c.Shots.Shoot = TakeScreenshot;
            c.Perf.WriteFiles = WritePerfFiles;
            c.Perf.Os = SystemInfo.operatingSystem;
            c.Perf.Version = "Unity " + Application.unityVersion;
            c.PerfWindow.Copy = text => { try { GUIUtility.systemCopyBuffer = text; } catch { } };
            // the first Nemesis / Boss Spawns / survey messages open their windows by themselves (the panels set Visible)
        }

        void TakeScreenshot(string ev, string relName)
        {
            try
            {
                string path = Path.Combine(DataDir(), relName);
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                ScreenCapture.CaptureScreenshot(path);
                PostLine(ShotsState.ToastText(Path.GetDirectoryName(path), streamer.Streamer));
            }
            catch (Exception e) { PostLine("Screenshot failed: " + e.Message); }
        }

        void WritePerfFiles(string stamp, string csv, string report)
        {
            try
            {
                string dir = DataDir();
                File.WriteAllText(Path.Combine(dir, PerfCore.CsvName(stamp)), csv);
                File.WriteAllText(Path.Combine(dir, PerfCore.TextName(stamp)), report);
            }
            catch (Exception e) { PostLine("Performance record not saved: " + e.Message); }
        }

        /// <summary>Per frame in the game: the hotkeys of streamer and cinema mode and the performance sample.</summary>
        void CommunityUpdate()
        {
            if (session == null) return;
            bool ctrl = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
            bool shift = Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift);
            if (!chatFocused && ctrl && shift)
            {
                if (Input.GetKeyDown(KeyCode.S)) streamer.ToggleStreamer();
                if (Input.GetKeyDown(KeyCode.H)) streamer.ToggleCinema();
            }
            var perf = session.Community.Perf;
            var open = new List<string>();
            foreach (var win in windows) if (win.Open) open.Add(win.GetType().Name);
            perf.Screen = UnityEngine.Screen.width + "x" + UnityEngine.Screen.height;
            perf.Frame(session.Now, Time.unscaledDeltaTime * 1000.0, GC.GetTotalMemory(false) / 1024.0, world.Creatures.Count, open);
        }

        /// <summary>A creature's name and bar are not drawn: the own name in streamer mode (sub-option), other players in cinema mode (sub-option).</summary>
        bool CommunityHidesName(Creature c)
        {
            if (c == null) return false;
            bool self = world.Player != null && c.Id == world.Player.Id;
            if (self) return streamer.HideOwnNameNow;
            return c.Type == 0 && streamer.HideOthersNow;
        }

        /// <summary>The green or dim border of a card that sits in a deck bag (game_cardborder).</summary>
        public string CardBorderColor(int deckItemId, int cardItemId)
        {
            var cb = session?.Community?.CardBorder;
            return cb == null ? null : CardBorderState.ColorOf(cb.Kind(deckItemId, cardItemId));
        }
    }
}
