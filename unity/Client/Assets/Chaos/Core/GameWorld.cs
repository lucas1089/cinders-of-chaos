// World, map and item utilities of the session (track O): the models of Core/WorldMarks.cs, WorldTravel.cs, WorldTiles.cs, WorldItems.cs and
// WorldItems2.cs, made once with the extended opcode layer. Kept in its own partial so the shared GameSession file stays small.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class WorldUtils
    {
        public readonly MapMarkState Marks;
        public readonly MapOverlayState Overlay;
        public readonly NpcTravel Travel;
        public readonly WaystoneState Waystone;
        public readonly TownPortalState Portal;
        public readonly HideoutState Hideout;
        public readonly TileOverlays Tiles;
        public readonly WeatherState Weather;
        public readonly NameplateState Plates;
        public readonly AutoLootState AutoLoot;
        public readonly PouchesState Pouches;
        public readonly OrbExchangeState Orbs;
        public readonly GambleState Gamble;
        public readonly EmberCacheState Ember;
        public readonly UnveilState Unveil;
        public readonly ItemFinderState Finder;
        public readonly LoadoutsState Loadouts;
        public readonly SpellSupportsState Supports;
        public readonly PactState Pact;
        public readonly CandlemarksState Candles;
        bool started;
        double lastScan;

        public WorldUtils(ExtOpcodes ext, Func<double> clock, Func<int> selfId)
        {
            Marks = new MapMarkState(ext) { Clock = clock, SelfId = selfId };
            Overlay = new MapOverlayState(ext);
            Travel = new NpcTravel(ext) { Clock = clock };
            Waystone = new WaystoneState(ext);
            Portal = new TownPortalState(ext);
            Hideout = new HideoutState(ext);
            Tiles = new TileOverlays(ext) { Clock = clock };
            Weather = new WeatherState(ext);
            Plates = new NameplateState(ext) { Clock = clock };
            AutoLoot = new AutoLootState(ext);
            Pouches = new PouchesState(ext) { Clock = clock };
            Orbs = new OrbExchangeState(ext) { Clock = clock };
            Gamble = new GambleState(ext) { Clock = clock };
            Ember = new EmberCacheState(ext);
            Unveil = new UnveilState(ext);
            Finder = new ItemFinderState(ext) { Clock = clock };
            Loadouts = new LoadoutsState(ext) { Clock = clock };
            Supports = new SpellSupportsState(ext) { Clock = clock };
            Pact = new PactState(ext);
            Candles = new CandlemarksState(ext) { Clock = clock };
        }

        /// <summary>The requests of a game start (the main client's onGameStart of each module).</summary>
        public void Start()
        {
            if (started) return;
            started = true;
            Marks.Hello();
            Tiles.Hello();
            Weather.Hello();
            AutoLoot.Sync();
            Pouches.Sync();
            Pact.Sync();
        }

        /// <summary>Called every frame with the world and the time (ms).</summary>
        public void Tick(World w, double now)
        {
            Weather.Tick(now);
            Tiles.Tick(now);
            Gamble.Tick(now);
            Finder.Tick();
            if (now - lastScan >= 250)
            {
                lastScan = now;
                Tiles.Scan(w, now);
                Weather.Covered = IsCovered(w);
            }
            var players = new List<uint>();
            if (w != null)
                foreach (var c in w.Creatures.Values) if (c.Type == 0 && c.Id != w.PlayerId) players.Add(c.Id);
            Plates.Tick(players);
        }

        /// <summary>The player's tile has a floor above it (g_map.isCovered): the tiles up the diagonal, one floor each.</summary>
        public static bool IsCovered(World w)
        {
            var me = w?.Player;
            if (me == null) return false;
            Pos p = me.Position;
            for (int i = 1; i <= p.Z; i++)
            {
                var t = w.Get(new Pos(p.X + i, p.Y + i, p.Z - i));
                if (t != null && t.Things.Count > 0) return true;
            }
            return false;
        }

        public void Clear()
        {
            started = false;
            Marks.Clear(); Overlay.Clear(); Travel.Clear(); Waystone.Clear(); Portal.Clear(); Hideout.Clear(); Tiles.Clear(); Weather.Clear(); Plates.Clear();
            AutoLoot.Clean(); Pouches.Clear(); Orbs.Clear(); Gamble.Clear(); Ember.Clear(); Unveil.Clear(); Finder.Clear(); Loadouts.Clear(); Supports.Clear(); Pact.Clear(); Candles.Clear();
        }
    }

    public sealed partial class GameSession
    {
        /// <summary>World, map and item utilities (marks, overlay, travel, waystone, portal, hideout, tile overlays, weather, plates, loot, pouches, exchange, gamble, cache, unveil, finder, loadouts, supports, pact, candles).</summary>
        public WorldUtils Utils { get; private set; }

        /// <summary>Called by the constructor, after Ext and Hud exist.</summary>
        void InitWorldUtils()
        {
            Utils = new WorldUtils(Ext, () => Now, () => (int)world.PlayerId);
            // casts that take time (Town Portal, a loadout switch) show on the cast bar like any other cast
            Action<string, double> start = (name, ms) => { if (ms > 0) Hud.Cast.Mine = new CastEntry { Name = name, Ms = Math.Min(ms, CastBar.MaxMs), Start = Now, Portal = true }; };
            Action<string> end = result => Hud.Cast.EndMine(result, 0, Now);
            Utils.Portal.CastStarted = start; Utils.Portal.CastEnded = end;
            Utils.Loadouts.CastStarted = start; Utils.Loadouts.CastEnded = end;
            // a build loaded from the Chaos Pact opens its preview in the passive tree (the tree window shows it)
            Utils.Pact.BuildCode = (slot, code) => Progress.Tree.PreviewBuild(code);
        }

        /// <summary>Called by Poll.</summary>
        void WorldUtilsPoll()
        {
            if (enteredAt >= 0 && Now - enteredAt > 2200) Utils.Start();
            Utils.Tick(world, Now);
        }
    }
}
