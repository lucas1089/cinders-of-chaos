// The NPC speech bubble and the walk-up to an NPC (phase 6, track V; client game_npctalk npctalk_logic.lua): the NPC's latest reply in a bubble over
// the NPC with a tail that points at it, long replies wrapped and the bubble kept inside the map; and Talk, which walks up to an NPC that is out of
// its talk radius and then greets it. Pure: the Unity side measures text and draws.
using System;
using System.Collections.Generic;
using System.Text;

namespace Chaos.Core
{
    public struct BubblePlace
    {
        public float X, Y, TailX, TailY;
        public bool Below;
    }

    public static class NpcBubble
    {
        /// <summary>The stock NPC handler's talk radius: further away an NPC neither hears nor answers.</summary>
        public const int TalkRange = 3;
        /// <summary>Walking up to an NPC gives up after this long.</summary>
        public const double ApproachTimeoutMs = 10000;
        /// <summary>The NPC forgets an idle player after 120 s; so does the bubble.</summary>
        public const double IdleMs = 120000;
        public const float TailW = 22, TailH = 12, MaxWidth = 300, MinWidth = 140, Pad = 8, LineH = 16;
        public const int MaxLines = 8;

        public static bool InRange(Pos a, Pos b, int range = TalkRange) => a.Z == b.Z && PathFinder.Cheb(a, b) <= range;

        /// <summary>Wraps a reply into lines no wider than `width` by the caller's measure (words are never cut unless one is wider than a line).</summary>
        public static List<string> Wrap(string text, float width, Func<string, float> measure)
        {
            var lines = new List<string>();
            text = (text ?? "").Replace("\r", "");
            foreach (string para in text.Split('\n'))
            {
                var cur = new StringBuilder();
                foreach (string word in para.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    string next = cur.Length == 0 ? word : cur + " " + word;
                    if (cur.Length > 0 && measure(next) > width) { lines.Add(cur.ToString()); cur.Clear(); next = word; }
                    // a single word wider than a line is cut by letters
                    while (measure(next) > width && next.Length > 1)
                    {
                        int cut = next.Length - 1;
                        while (cut > 1 && measure(next.Substring(0, cut)) > width) cut--;
                        lines.Add(next.Substring(0, cut));
                        next = next.Substring(cut);
                    }
                    cur.Clear();
                    cur.Append(next);
                }
                lines.Add(cur.ToString());
            }
            if (lines.Count > 1 && lines[lines.Count - 1].Length == 0) lines.RemoveAt(lines.Count - 1);
            return lines;
        }

        /// <summary>The lines that show: the last MaxLines of the reply (the start is what scrolls off).</summary>
        public static List<string> Visible(List<string> lines)
        {
            if (lines.Count <= MaxLines) return lines;
            var o = lines.GetRange(lines.Count - MaxLines, MaxLines);
            o[0] = "..." + o[0];
            return o;
        }

        /// <summary>Width of a bubble for the longest line, between MinWidth and MaxWidth (and never wider than the map less its margins).</summary>
        public static float WidthFor(float longestLine, float room)
        {
            float w = Math.Max(MinWidth, Math.Min(MaxWidth, longestLine + 2 * Pad));
            return Math.Max(60f, Math.Min(w, room));
        }

        /// <summary>The bubble's place: above the NPC with the tail's tip at `aboveX, aboveY` (the point over its name), or under it with the tip at `belowX, belowY` (its feet) when there is no
        /// room above; always inside `area`. The tail's top rows cover the bubble's rim.</summary>
        public static BubblePlace Place(float w, float h, float aboveX, float aboveY, float belowX, float belowY, float areaX, float areaY, float areaW, float areaH,
            float tailW = TailW, float tailH = TailH, float margin = 4)
        {
            const float overlap = 3;
            float minX = areaX + margin, maxX = areaX + areaW - margin - w;
            float minY = areaY + margin, maxY = areaY + areaH - margin - h;
            float x = (float)Math.Floor(aboveX - w / 2);
            x = Math.Max(minX, Math.Min(maxX, x));
            if (maxX < minX) x = minX;
            bool isBelow = false;
            float y = aboveY - tailH + overlap - h;
            if (y < minY)
            {
                float yb = belowY + tailH - overlap;
                if (yb <= maxY) { y = yb; isBelow = true; }
                else if (areaY + areaH - belowY > aboveY - areaY) { y = yb; isBelow = true; }
            }
            y = Math.Max(minY, Math.Min(Math.Max(minY, maxY), y));
            float tailX = Math.Max(x + 8, Math.Min(x + w - 8 - tailW, (float)Math.Floor(aboveX - tailW / 2)));
            float tailY = isBelow ? y - tailH + overlap : y + h - overlap;
            return new BubblePlace { X = x, Y = y, TailX = tailX, TailY = tailY, Below = isBelow };
        }

        /// <summary>Does the bubble stay? Open while the NPC is in sight, in range and the talk is not idle.</summary>
        public static bool Keep(bool npcInView, bool inRange, double nowMs, double lastActivityMs) =>
            npcInView && inRange && nowMs - lastActivityMs <= IdleMs;
    }

    /// <summary>Talk to an NPC from afar: walk to the nearest reachable tile within the talk radius, then say hi. Gives up after ApproachTimeoutMs or when the NPC leaves.</summary>
    public sealed class NpcApproach
    {
        public uint NpcId;
        public string NpcName = "";
        public double Started;
        public bool Active;

        public enum Step { Idle, Waiting, Greet, Failed }

        public void Start(uint npcId, string name, double now) { NpcId = npcId; NpcName = name ?? ""; Started = now; Active = true; }
        public void Cancel() { Active = false; }

        /// <summary>One frame: Greet once the player stands within the talk radius, Failed when the NPC is gone or the time ran out, else Waiting.</summary>
        public Step Update(bool npcInView, Pos me, Pos npc, double now)
        {
            if (!Active) return Step.Idle;
            if (!npcInView) { Active = false; return Step.Failed; }
            if (NpcBubble.InRange(me, npc)) { Active = false; return Step.Greet; }
            if (now - Started > NpcBubble.ApproachTimeoutMs) { Active = false; return Step.Failed; }
            return Step.Waiting;
        }

        /// <summary>The path to walk to talk to an NPC: to the nearest tile within the radius that can be reached (null: no way). An NPC already in range gives an empty list.</summary>
        public static List<Dir> PathTo(Pos me, Pos npc, Func<Pos, bool> walkable) => PathFinder.Find(me, npc, walkable, NpcBubble.TalkRange);
    }
}
