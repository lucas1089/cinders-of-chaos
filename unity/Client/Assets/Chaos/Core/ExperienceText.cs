// "You gained N experience points." (Player::addExperience, MESSAGE_EXPERIENCE, a text message with a position and the amount as the number). A party
// member's share and a kill's own experience come the same way. Read by the live check (O433 phase 22).
using System.Globalization;

namespace Chaos.Core
{
    public static class ExperienceText
    {
        /// <summary>True for "You gained 12 experience points." and the singular; the amount is the number. Other texts and numbers that do not parse give false.</summary>
        public static bool TryParse(string text, out long amount)
        {
            amount = 0;
            const string head = "You gained ";
            if (text == null || !text.StartsWith(head, System.StringComparison.Ordinal)) return false;
            int sp = text.IndexOf(' ', head.Length);
            if (sp < 0) return false;
            string rest = text.Substring(sp + 1);
            if (rest != "experience points." && rest != "experience point.") return false;
            return long.TryParse(text.Substring(head.Length, sp - head.Length), NumberStyles.None, CultureInfo.InvariantCulture, out amount);
        }
    }
}
