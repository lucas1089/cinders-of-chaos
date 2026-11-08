// Phase 8, track A (P0 and P1 gap lists): the pure rules of the hotbar frame and its key labels, the painted icons option, the toast pause and phone filter,
// the rarity ring of items in the live and HD-2D views, the draw size of monsters in those views, the top menu icons and the Admin button, the helper's preset
// key, and the store's look preview try-on. Each class names the main client file it follows. The Unity side is Unity/ChaosApp.Phase8A.cs.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    /// <summary>A rectangle in UI units (the Core has no UnityEngine).</summary>
    public struct RectD
    {
        public double X, Y, W, H;
        public RectD(double x, double y, double w, double h) { X = x; Y = y; W = w; H = h; }
        public double Right => X + W;
        public double Bottom => Y + H;
        public bool Contains(double x, double y) => x >= X && x < X + W && y >= Y && y < Y + H;
    }

    // ================================================================================================ game_hotbar
    /// <summary>The ornate frame of the central hotbar (game_hotbar hotbar.otui, hotbar_logic.lua): the iron body, a slot frame under every slot, the round sockets of Q and E,
    /// the key box of each slot. The art files are the main client's (client/overlay/modules/game_hotbar/images). Also the key label rectangle: the label of a slot must be
    /// tall enough for its font, whatever padding the window skin gives labels (the Q and E labels read as O and F when the box was 14 high and the skin padded the top).</summary>
    public static class HotbarFrame
    {
        public const string Dir = "game_hotbar/images/";
        public const string Body = Dir + "hotbar_body.png", Slot = Dir + "hotbar_slot.png", SlotReady = Dir + "hotbar_slot_ready.png",
            Socket = Dir + "hotbar_socket.png", Key = Dir + "hotbar_key.png", Gem = Dir + "hotbar_gem.png";
        public const int BodyBorder = 20, BodyW = 96, BodyH = 84, KeyW = 30, KeyH = 14, KeyBorder = 4, SlotFrame = 44, Button = 36, GemSize = 14;
        public const int KeyFont = 10;

        /// <summary>The key label of a slot: inside the key box at the top left, two pixels in, as tall as its font needs plus the line gap (never the old 14 pixels that cut the descenders).</summary>
        public static RectD KeyLabel(double slotX, double slotY, double slotW, int fontSize = KeyFont)
        {
            double h = Math.Max(KeyH, Math.Ceiling(fontSize * 1.6));
            return new RectD(slotX + 2, slotY, Math.Max(10, slotW - 2), h);
        }

        /// <summary>The key box (hotbar_key, 9-slice border 4) behind the label: as wide as the label text needs, at most the slot.</summary>
        public static RectD KeyBox(double slotX, double slotY, double slotW, string label)
        {
            double w = Math.Min(slotW, Math.Max(14, (label ?? "").Length * 7 + 10));
            return new RectD(slotX, slotY, Math.Min(w, KeyW * slotW / Button), KeyH);
        }

        /// <summary>The frame of one slot: the base button is 36 of 44 pixels, so the frame is the slot grown by 4/36 of its width on every side.</summary>
        public static RectD SlotFrameOf(double slotX, double slotY, double slotW, double slotH)
        {
            double padX = slotW * (SlotFrame - Button) / 2.0 / Button, padY = slotH * (SlotFrame - Button) / 2.0 / Button;
            return new RectD(slotX - padX, slotY - padY, slotW + 2 * padX, slotH + 2 * padY);
        }

        /// <summary>The iron body behind the whole row (the sockets included): the row's rectangle grown by pad.</summary>
        public static RectD BodyOf(double rowX, double rowY, double rowW, double rowH, double pad)
        {
            return new RectD(rowX - pad, rowY - pad, rowW + 2 * pad, rowH + 2 * pad);
        }

        /// <summary>The ready frame (hotbar_slot_ready) of a slot of the row: it holds something and is not on cooldown. The sockets always use the plain frame.</summary>
        public static bool Ready(HotSlot s, int cooldownSeconds, bool side) => !side && !s.IsEmpty && cooldownSeconds <= 0;

        public static string FramePath(bool side, bool ready) => side ? Socket : (ready ? SlotReady : Slot);
    }

    // ================================================================================================ painted icons (game_chaosspells, game_buffbar, game_passivetree)
    /// <summary>The client setting "Painted icons" (g_settings chaosPaintedIcons, off by default): a Chaos spell, a buff and a keystone or mastery node draw their painted picture
    /// (client/tools/gen_painted_icons.py). A name without a painted file keeps its normal icon. The files are client/overlay/data/images/game/spells_painted, buffs_painted
    /// and passivetree/painted_nodes.png.</summary>
    public static class PaintedIcons
    {
        public const string Pref = "chaos.painted";
        public const string NodeSheet = "images/passivetree/painted_nodes.png";
        public const int SpellSize = 32, BuffSize = 26, NodeCell = 64;

        /// <summary>The 32 px painted icon of a spell by its cell of the spell icon sheet (the client id): spells_painted/&lt;cell&gt;.png; null for no cell.</summary>
        public static string SpellPath(int cell) => cell > 0 ? ArtPaths.Data("images/game/spells_painted/" + cell.ToString(CultureInfo.InvariantCulture) + ".png") : null;

        /// <summary>The 26 px painted buff icon by the buff's own file name (BuffIcons.OwnName); null for a name that is not a plain file name.</summary>
        public static string BuffPath(string name) => name != null && BuffIcons.ValidName(name) ? ArtPaths.Data("images/game/buffs_painted/" + name + ".png") : null;

        public static string NodePath => ArtPaths.Data(NodeSheet);

        /// <summary>Which icon a picture request takes: the painted one when the option is on and the file exists, else the normal one.</summary>
        public static string Choose(bool on, string painted, Func<string, bool> exists, string normal)
        {
            if (on && painted != null && exists != null && exists(painted)) return painted;
            return normal;
        }

        /// <summary>The icon key of a passive node under the painted option (passivetree.lua paintedTreeIcon): the node's own key, or the class variant's key when it has an icon of its own.</summary>
        public static string NodeKey(string nodeKey, string variantKey, bool isStart, Func<string, bool> hasIcon)
        {
            if (!isStart && !string.IsNullOrEmpty(variantKey) && hasIcon != null && hasIcon(variantKey)) return variantKey;
            return nodeKey;
        }
    }

    // ================================================================================================ game_chaosnotify
    /// <summary>What the main client's toast does that the stack of ToastCenter did not: a press on a toast pauses its timer until the release (the pause ends when the cursor leaves it,
    /// so a release that never arrives cannot freeze it), a phone shows only the toasts that wait for an answer (notifyview.lua showOnPhone), the danger window has a close button.</summary>
    public static class ToastPause
    {
        /// <summary>Phones keep the invitations only (O401).</summary>
        public static bool ShowOnPhone(string type) => type == "PARTY_INVITE" || type == "CATACOMB_FREE";

        public static bool Shown(string type, bool phone) => !phone || ShowOnPhone(type);

        /// <summary>The state of a toast timer: Press starts a pause, Resume ends it (the paused time is added to the end time).</summary>
        public static void Press(Toast t, double now) { if (t != null && t.PausedAt < 0) t.PausedAt = now; }

        public static bool Resume(Toast t, double now)
        {
            if (t == null || t.PausedAt < 0) return false;
            t.StartAt += Math.Max(0, now - t.PausedAt);
            t.PausedAt = -1;
            return true;
        }

        /// <summary>Time left: frozen at the pressed moment while paused.</summary>
        public static double Left(Toast t, double now) => t.PausedAt >= 0 ? t.Left(t.PausedAt) : t.Left(now);

        public static double Fraction(Toast t, double now) => t.PausedAt >= 0 ? t.Fraction(t.PausedAt) : t.Fraction(now);
    }

    // ================================================================================================ game_itemrarity (live and HD-2D views)
    /// <summary>The rarity outline of items lying on the map in the live and HD-2D views (the classic view draws the sprite again tinted, MapItemOutline). Those views draw the sprites as
    /// meshes in a 3D scene, so the outline there is a ring drawn on the ground under the item: the same colour, the same pulse (Legendary, Divine and unique items), and a gold-white
    /// shimmer for Divine (the main client's metal shader, which Unity has no counterpart of).</summary>
    public static class RarityGlow
    {
        public const int DivineRarity = 10;
        public const double RingW = 0.78, RingH = 0.38;   // in tiles

        /// <summary>The ring colour (hex) of an item, null for none: the same rule as the classic outline.</summary>
        public static string RingColor(Item it) => MapItemOutline.Color(it);

        public static float Alpha(Item it, double nowMs) => MapItemOutline.Alpha(it, nowMs);

        public static bool IsDivine(Item it) => it != null && !ItemRarity.IsUnique(it) && ItemRarity.Of(it) == DivineRarity;

        /// <summary>The Divine shimmer: 0..1 sweeping slowly, 0 for any other item. The ring blends from its colour to white by this much.</summary>
        public static float Shimmer(Item it, double nowMs)
        {
            if (!IsDivine(it)) return 0f;
            return 0.5f + 0.5f * (float)Math.Sin(nowMs / 700.0);
        }

        /// <summary>The ring rectangle around a tile centre (px, py) for a tile of tilePx pixels: wider than high, as the ground under a standing item looks from the tilted view.</summary>
        public static RectD Ring(double px, double py, double tilePx)
        {
            double w = tilePx * RingW, h = tilePx * RingH;
            return new RectD(px - w / 2, py - h / 2 + tilePx * 0.12, w, h);
        }

        /// <summary>The item of a tile that gets the ring: the rarest thing lying there (a pile shows the best colour).</summary>
        public static Item Best(IEnumerable<Thing> things)
        {
            Item best = null; int rank = -1;
            if (things == null) return null;
            foreach (var t in things)
            {
                var it = t.Item;
                if (t.IsCreature || it == null || RingColor(it) == null) continue;
                int r = (ItemRarity.IsUnique(it) ? 100 : 0) + ItemRarity.Of(it);
                if (r > rank) { rank = r; best = it; }
            }
            return best;
        }
    }

    // ================================================================================================ game_monsterbar (live and HD-2D draw size)
    /// <summary>The draw size of monsters in the live and HD-2D views: the classic view scales the sprite (MonsterWorld.DrawScale); the scene views scale the quad about the feet.</summary>
    public static class SceneScale
    {
        /// <summary>A point scaled about a pivot (feet): used on the corners of every quad of a creature in the HD-2D mesh.</summary>
        public static void About(ref float x, ref float y, ref float z, float px, float py, float pz, float s)
        {
            if (s == 1f) return;
            x = px + (x - px) * s; y = py + (y - py) * s; z = pz + (z - pz) * s;
        }

        /// <summary>The scale a scene view uses for a creature: only monsters are scaled, never below ScaleMin; null or a missing hook gives 1.</summary>
        public static float For(Creature c, Func<Creature, float> hook)
        {
            if (c == null || c.Type != 1 || hook == null) return 1f;
            float s = hook(c);
            return float.IsNaN(s) || s <= 0f ? 1f : Math.Min(2f, Math.Max(MonsterWorld.ScaleMin, s));
        }

        /// <summary>The height of the name label above a scaled creature: the head moves with the scale.</summary>
        public static float Head(float height, float scale) => height * scale;
    }

    // ================================================================================================ client_chaos_topbar
    /// <summary>The per-entry icons of the top menu (chaos_topbar.lua entry(text, icon)): /images/chaos/small/topbutton_&lt;icon&gt;.png, 16 px. The table is the main client's, entry by entry.</summary>
    public static class TopMenuIcons
    {
        public const int RowSize = 16, ButtonSize = 16;
        public const string Dir = "images/chaos/small/topbutton_";

        static readonly Dictionary<string, string> ByText = new Dictionary<string, string>
        {
            { "Skills", "skills" }, { "Buff Bar", "skills" }, { "Spellbook", "spells" }, { "Spell List", "spells" }, { "Spell Supports", "spells" }, { "Passive Tree", "passivetree" },
            { "Achievements", "ranking" }, { "Pets", "vip" }, { "Transmog", "inventory" }, { "Cosmetics", "inventory" }, { "Town Portal", "minimap" }, { "Hideout", "minimap" },
            { "Character Info", "help" }, { "Services", "help" }, { "Inventory", "inventory" }, { "Outfit", "inventory" }, { "Portal Style", "inventory" },
            { "Battle List", "battlelist" }, { "Party", "vip" }, { "Party Frames", "vip" }, { "Hunt Tracker", "ranking" }, { "DPS Meter", "ranking" }, { "Hunt Analyser", "ranking" },
            { "Bestiary", "battlelist" }, { "Kill Tasks", "quests" }, { "Task Tracker", "quests" }, { "Loot Filter", "autoloot" }, { "Auto Loot", "autoloot" }, { "Minimap", "minimap" },
            { "Map Overlay", "minimap" }, { "Map Overlay Settings", "minimap" }, { "Map Markers", "minimap" }, { "Loot Splitter", "bank" }, { "Unjustified Points", "pvp" },
            { "Dungeons", "dungeons" }, { "Rifts", "dungeons" }, { "Infinity Tower", "infinitytower" }, { "Bounty Board", "quests" }, { "Daily Reward", "daily" }, { "Season", "events" },
            { "Season Pass", "battlepass" }, { "Arena", "pvp" }, { "Guild Siege", "pvp" }, { "Events", "events" }, { "Crafting Bench", "proficiency" }, { "Salvage", "proficiency" },
            { "Codex", "help" }, { "Item Finder", "help" }, { "Store", "market" }, { "Market", "market" }, { "Bank", "bank" }, { "Supply Stash", "stash" }, { "Auto Seller", "autoseller" },
            { "House", "bank" }, { "Ancestral Store", "market" }, { "Character Bazaar", "market" }, { "Guild", "vip" }, { "VIP List", "vip" }, { "Leaderboards", "ranking" },
            { "Inspect Player", "skills" }, { "Quest Log", "quests" }, { "Quest Tracker", "quests" }, { "Notifications", "notifications" }, { "Patch Notes", "events" },
            { "Options", "options" }, { "Hotkeys", "options" }, { "Sound", "options" }, { "Drop Feed", "options" }, { "Helper", "help" }, { "Server Info", "help" },
            { "Report a Bug", "help" }, { "Join Discord", "community" }, { "Credits", "help" }, { "New Window Look", "options" }, { "Logout", "logout" }, { "Exit", "exit" },
            { "Admin Panel", "admin" }, { "Charms", "skills" },
            // the entries of this client the main client words differently or has no icon for: the icon of the nearest one
            { "Containers", "inventory" }, { "Customise Character", "inventory" }, { "Chaos Pact", "events" }, { "Loadouts", "skills" }, { "Referral", "vip" },
            { "Fight", "battlelist" }, { "Nemesis", "battlelist" }, { "Boss Spawns", "battlelist" }, { "Next Goals", "quests" }, { "Goal Tracker", "quests" }, { "Group Queue", "vip" },
            { "Ember Descent", "dungeons" }, { "Rift Atlas", "dungeons" }, { "Waystone Atlas", "dungeons" }, { "Raid: Ashen Sepulchre", "dungeons" }, { "Scorched Marches", "pvp" },
            { "Battleground", "pvp" }, { "Invasions", "events" }, { "Weekly Chest", "daily" }, { "Ember Cache", "daily" }, { "Community", "events" }, { "Chronicle", "events" },
            { "Professions", "proficiency" }, { "Crafting Tables", "proficiency" }, { "Orb Exchange", "market" }, { "Candlemarks", "market" }, { "Channels", "vip" },
            { "Guild Wars", "pvp" }, { "Party Finder", "vip" }, { "Mentors", "vip" }, { "Help Search", "help" }, { "Streamer and cinema mode", "options" }, { "Performance", "options" },
            { "Screenshots", "options" },
        };

        static readonly Dictionary<string, string> ByCategory = new Dictionary<string, string>
        {
            { "character", "skills" }, { "hunt", "battlelist" }, { "adventure", "infinitytower" }, { "economy", "market" }, { "social", "vip" }, { "system", "options" }, { "admin", "admin" },
        };

        /// <summary>The icon name of a menu entry by its English text, null for none.</summary>
        public static string Of(string englishText) => englishText != null && ByText.TryGetValue(englishText, out var i) ? i : null;

        public static string OfCategory(string id) => id != null && ByCategory.TryGetValue(id, out var i) ? i : null;

        public static string Path(string icon, bool hover = false) => icon == null ? null : ArtPaths.Data(Dir + icon + (hover ? "_hover" : "") + ".png");

        public static int Count => ByText.Count;

        /// <summary>The names every icon file has to exist for (the tests check them against the client folder when it is there).</summary>
        public static IEnumerable<string> Names()
        {
            var seen = new HashSet<string>();
            foreach (var v in ByText.Values) if (seen.Add(v)) yield return v;
            foreach (var v in ByCategory.Values) if (seen.Add(v)) yield return v;
        }

        /// <summary>The width a menu row gives to the icon: the icon and a gap, so the text starts at the same place with or without the picture.</summary>
        public const float RowIndent = 22f;
    }

    /// <summary>The separate Admin button of the top menu (chaos_topbar.lua category "admin"): shown to staff only, with the Admin Panel entry.</summary>
    public static class TopMenuAdmin
    {
        public const string Id = "admin", Text = "Admin", PanelEntry = "Admin Panel";

        /// <summary>The number of category buttons: the menu's own categories, Windows, and the Admin button for staff.</summary>
        public static int ButtonCount(int categories, bool staff) => categories + 1 + (staff ? 1 : 0);

        /// <summary>The button index of Admin (after Windows), -1 when it is not shown.</summary>
        public static int Index(int categories, bool staff) => staff ? categories + 1 : -1;
    }

    // ================================================================================================ game_helper
    /// <summary>The helper's preset key (helper.lua toggleShooterPreset, bound to a hotkey of the main client's hotkey window): the key cycles the shooter presets in alphabetical order and tells
    /// the new one. No default key: the player chooses it, per character.</summary>
    public static class HelperPresetKey
    {
        public const string PrefPrefix = "chaos.helper.presetkey.";

        public static string PrefKey(string character) => PrefPrefix + (character ?? "").ToLowerInvariant();

        static readonly HashSet<string> Refused = new HashSet<string>
        {
            "None", "Escape", "Return", "KeypadEnter", "Backspace", "Tab", "Space", "Mouse0", "Mouse1", "Mouse2", "Mouse3", "Mouse4", "Mouse5", "Mouse6",
            "LeftShift", "RightShift", "LeftControl", "RightControl", "LeftAlt", "RightAlt", "LeftCommand", "RightCommand",
            "UpArrow", "DownArrow", "LeftArrow", "RightArrow", "W", "A", "S", "D", "Q", "E",   // the walking keys and the hotbar side slots keep their job
        };

        /// <summary>Can a key (a KeyCode name) be the preset key: any F key, a digit or a letter that the game does not use, never a movement or modifier key.</summary>
        public static bool Valid(string keyName)
        {
            if (string.IsNullOrEmpty(keyName) || Refused.Contains(keyName)) return false;
            if (keyName.Length >= 2 && keyName[0] == 'F' && int.TryParse(keyName.Substring(1), NumberStyles.None, CultureInfo.InvariantCulture, out int f) && f >= 1 && f <= 15)
                return false;   // F1 to F12 are the hotbar's and the windows'
            if (keyName.Length == 1 && char.IsLetter(keyName[0])) return true;
            if (keyName.StartsWith("Alpha", StringComparison.Ordinal) && keyName.Length == 6 && char.IsDigit(keyName[5])) return true;
            if (keyName.StartsWith("Keypad", StringComparison.Ordinal)) return true;
            return keyName == "BackQuote" || keyName == "Minus" || keyName == "Equals" || keyName == "LeftBracket" || keyName == "RightBracket"
                || keyName == "Semicolon" || keyName == "Quote" || keyName == "Comma" || keyName == "Period" || keyName == "Slash" || keyName == "Backslash"
                || keyName == "Insert" || keyName == "Delete" || keyName == "Home" || keyName == "End" || keyName == "PageUp" || keyName == "PageDown";
        }

        /// <summary>The text on the button: the key, or "None".</summary>
        public static string Label(string keyName) => string.IsNullOrEmpty(keyName) ? Loc.T("None") : keyName;

        /// <summary>Cycles to the next preset of the config (alphabetical) and returns the message the main client shows ("Preset: Name"); null for a config without presets.</summary>
        public static string Cycle(HelperConfig cfg)
        {
            if (cfg == null) return null;
            string next = HelperProfiles.Next(cfg, cfg.SelectedProfile);
            if (next == null || !cfg.SelectProfile(next)) return null;
            return Loc.T("Preset: {0}", next);
        }
    }

    // ================================================================================================ game_shop (look preview try-on)
    /// <summary>The TRY ON button of an offer whose look shows on the character in the look preview panel (game_shop tryon.lua plan): outfits, addons, mounts, wings, auras, shaders, outlines,
    /// effects and footprints, or a bundle holding one of them. The panel opens with the offer's option for ten seconds and goes back to the character as worn; nothing is bought.</summary>
    public static class StoreTryPanel
    {
        public const double Ms = StoreTryOn.Ms;
        static readonly HashSet<string> Worn = new HashSet<string> { "outfit", "addons", "mount", "wings", "aura", "shader", "outline", "effects", "footprint" };

        /// <summary>Does the option put something on the player's own character (tryon.lua worn).</summary>
        public static bool IsWorn(PreviewOption opt)
        {
            if (opt == null) return false;
            if (opt.Kind == "bundle")
            {
                if (opt.Parts != null) foreach (var p in opt.Parts) if (p != null && Worn.Contains(p.Kind)) return true;
                return false;
            }
            return Worn.Contains(opt.Kind);
        }

        /// <summary>What a TRY ON press does for an offer: the panel (a worn look), the server's effect (preview.effect), the name plate frame; Show says whether the button exists.</summary>
        public sealed class Plan { public bool Panel, Server, Plate, Show; }

        public static Plan PlanOf(StoreOffer o, bool hasPanel, bool hasPlate)
        {
            var p = new Plan();
            if (o == null) return p;
            p.Panel = hasPanel && IsWorn(o.Look);
            p.Server = o.PreviewEffect;
            p.Plate = hasPlate && !p.Server && PlateTry.Frame(o.Look) != null;
            p.Show = p.Panel || p.Server || p.Plate;
            return p;
        }

        /// <summary>The panel's option while a try runs, and back to the character as worn (null) when the ten seconds are over.</summary>
        public static PreviewOption OptionAt(PreviewOption tried, double until, double now) => tried != null && now < until ? tried : null;

        public static bool Over(double until, double now) => until > 0 && now >= until;
    }
}
