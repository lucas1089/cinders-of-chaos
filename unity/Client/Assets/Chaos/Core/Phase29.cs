// Phase 29 (2026-11-09): parity with the main client fixes of that day, and the rules that keep a new login clean.
//   StackCountLook  inventory / container stack counts: bright, not smaller than the slot's other text, with an outline (game_bagpanel: #f2e8d5, 11 px)
//   PurseButton     the Purse entry of the inventory window: store purchases land in inventory slot 11 (server store_delivery.lua), a use of that item opens it
//   SessionStamp    a time taken on one session's clock; a new session starts its clock at zero, so an old stamp must never block the new one
using System;

namespace Chaos.Core
{
    /// <summary>How a stack count is drawn over an item sprite. The main client's bag panel moved the count from a dim #6b6258 9 px to #f2e8d5 11 px
    /// (owner 2026-11-09: counts were unreadable). Unity had white 12 px with a one pixel black shadow on the lower right; this makes the colour
    /// the same cream, keeps the size at or above every other text of a slot and draws the outline on all four sides.</summary>
    public static class StackCountLook
    {
        /// <summary>The count colour, 0xRRGGBB: the bag panel's cream.</summary>
        public const uint Rgb = 0xF2E8D5;
        public const string Hex = "#f2e8d5";
        /// <summary>The count's font size in pixels: never below the main client's 11.</summary>
        public const int FontSize = 12;
        /// <summary>The size of the other text of a slot (the faint slot name, the hotbar mark): the count is at least this big.</summary>
        public const int SlotTextSize = 11;
        /// <summary>The outline: the offsets, in pixels, of the dark copies drawn under the count (four sides and the lower right shadow).</summary>
        public static readonly int[][] Outline = { new[] { -1, 0 }, new[] { 1, 0 }, new[] { 0, -1 }, new[] { 0, 1 }, new[] { 1, 1 } };
        /// <summary>The outline colour alpha: dark enough to read on a white sprite, a light one on a black slot.</summary>
        public const float OutlineAlpha = 0.95f;

        /// <summary>The text of a count: the number, or "" for a single item or none (the main client draws nothing below 2).</summary>
        public static string Text(int count) => count > 1 ? count.ToString(System.Globalization.CultureInfo.InvariantCulture) : "";

        /// <summary>The count of a carried item shown on the hotbar: 0 shows (greyed red), 1 does not.</summary>
        public static bool HotbarShows(int have) => have != 1;

        /// <summary>The colour of a hotbar count: red when none is carried, else the cream.</summary>
        public static uint HotbarRgb(int have) => have <= 0 ? 0xFF7366u : Rgb;

        /// <summary>Contrast ratio (WCAG) of the count against the darkest slot fill (0x1C171F): the readability rule the tests keep.</summary>
        public static double Contrast(uint fg, uint bg)
        {
            double a = Luminance(fg), b = Luminance(bg);
            double hi = Math.Max(a, b), lo = Math.Min(a, b);
            return (hi + 0.05) / (lo + 0.05);
        }

        static double Luminance(uint rgb)
        {
            double Ch(int shift)
            {
                double c = ((rgb >> shift) & 0xFF) / 255.0;
                return c <= 0.03928 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4);
            }
            return 0.2126 * Ch(16) + 0.7152 * Ch(8) + 0.0722 * Ch(0);
        }
    }

    /// <summary>The Purse button of the inventory window. The base client's inventory window held a purse button that the Chaos panel replaced; store
    /// purchases are delivered to the purse (server store_delivery.lua), so a player must be able to open it. The main client's button uses the item of
    /// inventory slot 11 (the engine's store inbox, item 26052 on the server, a container): the same request is sent here.</summary>
    public static class PurseButton
    {
        /// <summary>The inventory slot of the purse (the 10.98 protocol's store inbox slot).</summary>
        public const int Slot = 11;
        /// <summary>The server item id of the purse (client id differs by pair; the slot is what counts).</summary>
        public const int ServerItemId = 26052;

        /// <summary>The item in the purse slot, or null when the server has not sent one (a character with no store purchase may have none).</summary>
        public static Item Held(Item[] inventory) => inventory != null && Slot < inventory.Length ? inventory[Slot] : null;

        public static bool Has(Item[] inventory) => Held(inventory) != null;

        /// <summary>The tooltip of the button, like the main client's.</summary>
        public static string Tooltip => Loc.T("Opens your purse. What you buy in the store is delivered there.");

        /// <summary>What the main client says when the slot is empty.</summary>
        public static string NoPurse => Loc.T("You have no purse.");
    }

    public sealed partial class GameSession
    {
        /// <summary>Opens the purse: the same request as a click on the main client's purse button (use the item of slot 11; a container opens in the given window id).
        /// False when the purse slot is empty (the caller says "You have no purse.").</summary>
        public bool UsePurse(byte containerId)
        {
            var it = PurseButton.Held(parser.Inventory);
            if (it == null) return false;
            UseItem(InventoryPos(PurseButton.Slot), (ushort)it.Id, (byte)PurseButton.Slot, containerId);
            return true;
        }
    }

    /// <summary>A moment taken on a session's clock. A GameSession's clock (Now) starts at zero at each login, so a stamp from the old session can lie far in
    /// the new session's future: "now - stamp >= gap" stays false until the new session is as old as the old one. The loot label scan, the loot beams and the monster
    /// tier question of the Unity glue all went quiet after a death and a new login for that reason. A stamp that knows its session says "due" for any other one.</summary>
    public sealed class SessionStamp
    {
        object owner;
        double at = double.NegativeInfinity;

        /// <summary>True when the stamp is from another session (or was never set), or when at least gapMs passed on this session's clock since it was set.</summary>
        public bool Due(object session, double nowMs, double gapMs)
        {
            if (!ReferenceEquals(owner, session) || session == null) return true;
            return nowMs < at || nowMs - at >= gapMs;   // a clock that ran back is a new clock too
        }

        public void Mark(object session, double nowMs) { owner = session; at = nowMs; }

        /// <summary>Due now whatever the clock says.</summary>
        public void Reset() { owner = null; at = double.NegativeInfinity; }

        public bool IsSet => owner != null;
    }
}
