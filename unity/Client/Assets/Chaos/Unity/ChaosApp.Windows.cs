using System.Collections.Generic;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>A movable game window. Each window lives in its own file and is listed in ChaosApp.MakeWindows.</summary>
    public abstract class GameWindow
    {
        public abstract string Title { get; }
        /// <summary>Ctrl + this key opens and closes the window (None: no hotkey).</summary>
        public virtual KeyCode Hotkey => KeyCode.None;
        /// <summary>False for a window that opens by itself and has no place in the Windows list of the top menu (a HUD).</summary>
        public virtual bool InMenu => true;
        public bool Open;
        /// <summary>Where the window is, in UI units (720 px of height is scale 1). Set a default in Place.</summary>
        public Rect Area;
        bool placed;

        /// <summary>The first position on a w x h UI screen.</summary>
        protected abstract Rect Place(float w, float h);
        /// <summary>Draws the content. inner is the area under the title bar, in UI units.</summary>
        protected abstract void Body(ChaosApp app, Rect inner);
        /// <summary>Clears what the window remembers of the last character.</summary>
        public virtual void Reset() { }
        /// <summary>Called on every OnGUI pass for every window, open or not (for example to open itself on a server message).</summary>
        public virtual void Tick(ChaosApp app) { }

        internal void Draw(ChaosApp app, int id, float w, float h)
        {
            if (!placed) { Area = Place(w, h); placed = true; }
            // keep the title bar on screen
            Area.x = Mathf.Clamp(Area.x, 0, Mathf.Max(0, w - Area.width));
            Area.y = Mathf.Clamp(Area.y, 0, Mathf.Max(0, h - 24));
            Area = GUI.Window(id, Area, _ =>
            {
                ChaosApp.Fill(new Rect(0, 0, Area.width, Area.height), new Color(0.04f, 0.03f, 0.05f, 0.92f));
                ChaosApp.Fill(new Rect(0, 0, Area.width, 24), new Color(0.16f, 0.09f, 0.06f, 1f));
                GUI.Label(new Rect(8, 2, Area.width - 40, 22), Title, app.TitleStyle);
                if (GUI.Button(new Rect(Area.width - 26, 2, 22, 20), "x")) Open = false;
                Body(app, new Rect(4, 28, Area.width - 8, Area.height - 32));
                GUI.DragWindow(new Rect(0, 0, Area.width - 30, 24));
            }, GUIContent.none, GUIStyle.none);
        }
    }

    public sealed partial class ChaosApp
    {
        readonly List<GameWindow> windows = new List<GameWindow>();
        public GUIStyle TitleStyle => titleStyle;
        public GUIStyle SmallStyle => small;
        public SpriteAtlas Atlas => atlas;
        public Chaos.Core.DatFile Dat => dat;
        public Chaos.Core.World World => world;
        public Chaos.Core.GameSession Session => session;

        /// <summary>Every game window, in toolbar order. Add a new window here (one line).</summary>
        void MakeWindows()
        {
            windows.Add(new EquipmentWindow());
            windows.Add(new ContainersWindow());
            windows.Add(new SkillsWindow());
            windows.Add(new PassiveTreeWindow());
            windows.Add(new GoalsWindow());
            windows.Add(new GoalTrackerWindow());
            windows.Add(new HuntWindow());
            windows.Add(new RiftWindow());
            windows.Add(new InfoWindow());
            windows.Add(new BattleListWindow());
            windows.Add(new MinimapWindow());
            windows.Add(new HotkeyBarWindow());
            windows.Add(new SpellbookWindow());
            windows.Add(new NpcTalkWindow());
            windows.Add(new NpcTradeWindow());
            windows.Add(new PartyFramesWindow());
            windows.Add(new ChannelsWindow());
            windows.Add(new FightWindow());
            windows.Add(new OptionsWindow());
            windows.Add(new OutfitWindow());
            windows.Add(new BankWindow());
            windows.Add(new StashWindow());
            windows.Add(new StoreWindow());
            windows.Add(new HelperWindow());
            windows.Add(new DeathRecapWindow());
            windows.Add(new LootWindow());
            // endgame activities (track L): Core/Endgame*.cs, Windows/EndgameWindows[ABC].cs
            windows.Add(new TowerWindow()); windows.Add(new TowerPanelWindow());
            windows.Add(new DungeonsWindow()); windows.Add(new DungeonCounterWindow());
            windows.Add(new RaidWindow()); windows.Add(new RaidHudWindow()); windows.Add(new RaidCalloutWindow());
            windows.Add(new DescentWindow()); windows.Add(new DescentHudWindow()); windows.Add(new DescentOfferWindow()); windows.Add(new DescentShopWindow());
            windows.Add(new RiftAtlasWindow()); windows.Add(new WaystoneAtlasWindow());
            windows.Add(new InvasionWindow()); windows.Add(new InvasionHudWindow());
            windows.Add(new SiegeWindow()); windows.Add(new SiegeHudWindow());
            windows.Add(new ArenaWindow()); windows.Add(new ArenaHudWindow());
            windows.Add(new BattlegroundWindow()); windows.Add(new BattlegroundHudWindow()); windows.Add(new BattlegroundBoardWindow());
            windows.Add(new PvpZoneWindow()); windows.Add(new PvpZoneConfirmWindow()); windows.Add(new PvpZoneHudWindow());
            windows.Add(new BountyWindow());
        }

        /// <summary>The window of that class (made on first use), for windows that work together.</summary>
        public T FindWindow<T>() where T : GameWindow
        {
            if (windows.Count == 0) MakeWindows();
            foreach (var win in windows) if (win is T t) return t;
            return null;
        }

        static Rect ToolbarRect(float w) => new Rect(w - 104 - 76 * 7, 8, 76 * 7, 30);

        void DrawWindows(float w, float h, float scale)
        {
            if (windows.Count == 0) MakeWindows();
            foreach (var win in windows) win.Tick(this);
            TopbarGui(w, h, scale);   // ChaosApp.Progression.cs: category buttons, drop-downs, new unlocks
            for (int i = 0; i < windows.Count; i++)
            {
                var win = windows[i];
                if (!win.Open) continue;
                win.Draw(this, 1000 + i, w, h);
                uiRects.Add(Scaled(win.Area, scale));
            }
        }

        void ResetWindows() { foreach (var win in windows) win.Reset(); }

        /// <summary>Draws an item sprite (first frame, first pattern) into r, with its count when above 1.</summary>
        public void DrawItem(Rect r, ushort id, int count)
        {
            var t = dat?.Item(id);
            if (t == null || atlas == null) return;
            var g = t.Idle;
            int px = 0, py = 0;
            if (t.Stackable && g.PatternX * g.PatternY >= 8) { int s = MapView.StackIndex(count); px = s % 4; py = s / 4; }
            // a w x h item is drawn whole, shrunk to the slot; cells go right-to-left and bottom-to-top from the anchor
            int n = Mathf.Max(g.Width, g.Height);
            float cell = r.width / n;
            for (int layer = 0; layer < g.Layers; layer++)
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                    {
                        int slot = atlas.Sprite(g.Sprite(ww, hh, layer, px, py, 0, 0));
                        if (slot == 0) continue;
                        var uv = atlas.Uv(slot);
                        var cr = new Rect(r.x + (n - 1 - ww) * cell, r.y + (n - 1 - hh) * cell, cell, cell);
                        // the atlas UVs are bottom-up like the map mesh: DrawTextureWithTexCoords takes them as they are
                        GUI.DrawTextureWithTexCoords(cr, atlas.Texture, uv);
                    }
            if (count > 1)
            {
                var st = new GUIStyle(small) { alignment = TextAnchor.LowerRight, fontSize = 12, fontStyle = FontStyle.Bold };
                st.normal.textColor = Color.black;
                GUI.Label(new Rect(r.x + 1, r.y + 1, r.width, r.height), count.ToString(), st);
                st.normal.textColor = Color.white;
                GUI.Label(r, count.ToString(), st);
            }
        }
    }
}
