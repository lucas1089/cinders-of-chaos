// Phase 8, track A: the Unity side of the P0 and P1 gap lists. The rules are Core/Phase8A.cs, Core/Phase8ATip.cs, Core/Phase8ATree.cs.
//   hotbar        the ornate frame pictures (body, slot frames, sockets, key boxes) and the key label that is no longer cut
//   painted       the "Painted icons" option for spells and buffs (the passive tree reads it too)
//   tooltip       the card layout of the item tooltip
//   rarity        a ring under rare items in the live and HD-2D views, ground labels in HD-2D (TileScreenPx)
//   topbar        the icon of each menu entry and button
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        /// <summary>Every frame (called from Phase7YUpdate): the scene views' monster draw size, the phone flag of the toasts, the auto build's clock.</summary>
        void Phase8AUpdate()
        {
            using var _slow = SlowCalls.Scope("Phase8AUpdate", "Update");
            ToastCenter.Phone = Application.isMobilePlatform;
            if (hd2dView != null) hd2dView.CreatureScale = MonsterScaleFor;
            var flc = frontLive != null ? frontLive.GetComponent<FrontLiveCreatures>() : null;
            if (flc != null) flc.CreatureScale = MonsterScaleFor;
            var tree = session?.Progress?.Tree;
            if (tree != null) tree.Auto.Clock = () => session.Now;
        }

        /// <summary>True while a text field or the chat line has the keyboard (the helper's preset key must not fire then).</summary>
        public bool TypingNow => chatFocused || TextEditing;

        // ------------------------------------------------------------------------------------ hotbar frame
        /// <summary>A picture of the main client's overlay into r; false when the file is missing.</summary>
        public bool DrawArt(string rel, Rect r, bool smooth = true, Color? tint = null)
        {
            var t = ArtTexture(rel, smooth);
            if (t == null) return false;
            var old = GUI.color;
            GUI.color = tint ?? Color.white;
            GUI.DrawTexture(r, t, ScaleMode.StretchToFill, true);
            GUI.color = old;
            return true;
        }

        /// <summary>A picture cut in nine (edge pixels of a texW x texH picture) over r; false when the file is missing.</summary>
        public bool DrawNineArt(string rel, Rect r, float edge, int texW, int texH, bool smooth = true)
        {
            var t = ArtTexture(rel, smooth);
            if (t == null) return false;
            float e = Mathf.Max(1f, Mathf.Min(edge, r.height / 2f - 0.5f, r.width / 2f - 0.5f));
            NineSliceEdges(t, r, e, e, e, e, edge / texW, edge / texH, edge / texW, edge / texH, Color.white);
            return true;
        }

        /// <summary>The iron body behind the hotbar row; false (nothing drawn) when its picture is not there.</summary>
        public bool DrawHotbarBody(RectD body) => DrawNineArt(HotbarFrame.Body, new Rect((float)body.X, (float)body.Y, (float)body.W, (float)body.H), HotbarFrame.BodyBorder * Mathf.Min(1f, (float)body.H / HotbarFrame.BodyH), HotbarFrame.BodyW, HotbarFrame.BodyH);

        /// <summary>The gem on the top edge of the iron body (hotbar_gem, 14 px at the bar's scale).</summary>
        public void DrawHotbarGem(RectD body, float scalePercent)
        {
            float sz = HotbarFrame.GemSize * scalePercent / 100f;
            DrawArt(HotbarFrame.Gem, new Rect((float)(body.X + body.W / 2) - sz / 2f, (float)body.Y - sz * 5f / 14f, sz, sz));
        }

        /// <summary>The frame under one slot (the plain, the ready or the socket picture); false when the picture is not there.</summary>
        public bool DrawHotbarSlotFrame(Rect slot, bool side, bool ready)
        {
            var f = HotbarFrame.SlotFrameOf(slot.x, slot.y, slot.width, slot.height);
            return DrawArt(HotbarFrame.FramePath(side, ready), new Rect((float)f.X, (float)f.Y, (float)f.W, (float)f.H));
        }

        /// <summary>The key box behind a slot's key label (9-slice of hotbar_key).</summary>
        public bool DrawHotbarKeyBox(Rect slot, string label)
        {
            var b = HotbarFrame.KeyBox(slot.x, slot.y, slot.width, label);
            return DrawNineArt(HotbarFrame.Key, new Rect((float)b.X, (float)b.Y, (float)b.W, (float)b.H), HotbarFrame.KeyBorder, HotbarFrame.KeyW, HotbarFrame.KeyH);
        }

        // ------------------------------------------------------------------------------------ painted icons
        /// <summary>The painted 32 px icon of a spell cell when the option is on and the file is there, else null.</summary>
        Texture2D PaintedSpellTexture(int cell)
        {
            if (!VisualPrefs.Painted || cell <= 0) return null;
            return ArtTexture(PaintedIcons.SpellPath(cell), true);
        }

        Texture2D PaintedBuffTexture(string name)
        {
            if (!VisualPrefs.Painted) return null;
            string p = PaintedIcons.BuffPath(name);
            return p == null ? null : ArtTexture(p);
        }

        // ------------------------------------------------------------------------------------ item tooltip card
        GUIStyle cardText, cardTitle, cardSmall, cardCenter;

        void CardStyles()
        {
            if (cardText != null) return;
            cardText = new GUIStyle(small) { fontSize = 12, richText = true, wordWrap = false, clipping = TextClipping.Clip, alignment = TextAnchor.MiddleLeft, padding = new RectOffset(0, 0, 0, 0) };
            cardCenter = new GUIStyle(cardText) { alignment = TextAnchor.MiddleCenter };
            cardTitle = new GUIStyle(cardCenter) { fontSize = 16, fontStyle = FontStyle.Bold };
            cardSmall = new GUIStyle(cardCenter) { fontSize = 10, fontStyle = FontStyle.Bold };
        }

        /// <summary>Plans the card of a tip for the width: boxes and total height.</summary>
        List<CardBox> PlanCard(TipCard card, float width, IList<TipLine> notes, out float height)
        {
            CardStyles();
            Func<string, int, double> measure = (text, size) =>
            {
                cardText.fontSize = size;
                double w = cardText.CalcSize(new GUIContent(text ?? "")).x;
                cardText.fontSize = 12;
                return w;
            };
            var boxes = TipCardLayout.Plan(card, width, measure, out double h, notes);
            height = (float)h;
            return boxes;
        }

        static Rect R(RectD r, Rect origin) => new Rect(origin.x + (float)r.X, origin.y + (float)r.Y, (float)r.W, (float)r.H);

        static string RichParts(string[] parts)
        {
            var sb = new System.Text.StringBuilder();
            for (int i = 0; parts != null && i + 1 < parts.Length; i += 2)
                if (parts[i].Length > 0) sb.Append("<color=").Append(Hex(parts[i + 1])).Append('>').Append(RichSafe(parts[i])).Append("</color>");
            return sb.ToString();
        }

        void DrawCard(Rect r, TipCard card, List<CardBox> boxes)
        {
            CardStyles();
            Color accent = HexColor(card.TitleColor, new Color(0.5f, 0.4f, 0.2f));
            // the rarity glow: a soft halo in the title colour round the card (a plain item keeps the brown frame)
            bool plain = card.TitleColor == TipLines.Normal;
            if (!plain)
                for (int i = 3; i >= 1; i--) Fill(new Rect(r.x - i - 1, r.y - i - 1, r.width + 2 * i + 2, r.height + 2 * i + 2), new Color(accent.r, accent.g, accent.b, 0.07f * (4 - i)));
            Fill(new Rect(r.x - 1, r.y - 1, r.width + 2, r.height + 2), plain ? new Color(0.5f, 0.4f, 0.2f, 0.9f) : new Color(accent.r, accent.g, accent.b, 0.85f));
            Fill(r, new Color(0.05f, 0.04f, 0.06f, 0.97f));
            foreach (var b in boxes)
            {
                var br = R(b.R, r);
                switch (b.Kind)
                {
                    case "title":
                        GUI.Label(br, "<color=" + Hex(b.Color) + ">" + RichSafe(b.Text) + "</color>", cardTitle);
                        break;
                    case "kind":
                        GUI.Label(br, "<color=" + Hex(b.Color) + ">" + RichSafe(b.Text) + "</color>", cardSmall);
                        break;
                    case "line": case "flag":
                        cardCenter.fontSize = b.Size > 0 ? b.Size : 11;
                        GUI.Label(br, "<color=" + Hex(b.Color) + ">" + RichSafe(b.Text) + "</color>", cardCenter);
                        break;
                    case "sep":
                        Fill(br, new Color(1f, 1f, 1f, 0.12f));
                        break;
                    case "tile":
                    {
                        Fill(br, new Color(0.1f, 0.085f, 0.11f, 1f));
                        Fill(new Rect(br.x, br.y, br.width, 1), new Color(1f, 1f, 1f, 0.1f));
                        cardSmall.fontSize = 9;
                        GUI.Label(new Rect(br.x, br.y + 3, br.width, 12), "<color=" + Hex(TipLines.Dim) + ">" + RichSafe(TipCard.Caps(b.Caption)) + "</color>", cardSmall);
                        cardCenter.fontSize = b.Hero ? 18 : 14;
                        GUI.Label(new Rect(br.x, br.y + 15, br.width, br.height - 16), "<color=" + Hex(b.Hero ? TipLines.Gold : TipLines.Text) + ">" + RichSafe(b.Text) + "</color>", cardCenter);
                        break;
                    }
                    case "effect":
                        Fill(br, new Color(0.1f, 0.085f, 0.11f, 1f));
                        cardCenter.fontSize = 13;
                        GUI.Label(br, "<color=" + Hex(b.Color) + ">" + RichSafe(b.Text) + "</color>", cardCenter);
                        break;
                    case "extra":
                        cardCenter.fontSize = 11;
                        GUI.Label(br, RichParts(b.Parts), cardCenter);
                        break;
                    case "caption": case "fitcaption":
                        cardSmall.fontSize = 10;
                        cardSmall.alignment = TextAnchor.MiddleLeft;
                        GUI.Label(br, "<color=" + Hex(b.Color) + ">" + RichSafe(b.Text) + "</color>", cardSmall);
                        cardSmall.alignment = TextAnchor.MiddleCenter;
                        break;
                    case "row":
                    {
                        float x = br.x;
                        if (b.Tag.Length > 0)
                        {
                            Color tc = b.Top ? new Color(0.36f, 0.81f, 0.36f) : HexColor(b.TagColor, Color.gray);
                            Fill(new Rect(x, br.y + 2, 24, br.height - 4), new Color(tc.r, tc.g, tc.b, 0.18f));
                            cardSmall.fontSize = 9;
                            GUI.Label(new Rect(x, br.y, 24, br.height), "<color=" + Hex("#" + ColorUtility.ToHtmlStringRGB(tc)) + ">" + RichSafe(b.Tag) + "</color>", cardSmall);
                            x += 28;
                        }
                        float right = br.xMax;
                        if (b.Range.Length > 0)
                        {
                            cardText.alignment = TextAnchor.MiddleRight;
                            GUI.Label(new Rect(br.xMax - 70, br.y, 70, br.height), "<color=" + Hex(TipLines.Dim) + ">[" + RichSafe(b.Range) + "]</color>", cardText);
                            cardText.alignment = TextAnchor.MiddleLeft;
                            right -= 72;
                        }
                        cardText.fontSize = 12;
                        string rich = b.Parts != null ? RichParts(b.Parts) : "<color=" + Hex(b.Color) + ">" + RichSafe(b.Text) + "</color>";
                        GUI.Label(new Rect(x, br.y, Mathf.Max(10, right - x), br.height), rich, cardText);
                        break;
                    }
                    case "chip":
                    {
                        Color cc = HexColor(b.Color, Color.white);
                        Fill(br, new Color(0.14f, 0.11f, 0.12f, 1f));
                        Fill(new Rect(br.x, br.y, br.width, 1), new Color(cc.r, cc.g, cc.b, b.Low ? 0.9f : 0.35f)); Fill(new Rect(br.x, br.yMax - 1, br.width, 1), new Color(cc.r, cc.g, cc.b, b.Low ? 0.9f : 0.35f));
                        Fill(new Rect(br.x, br.y, 1, br.height), new Color(cc.r, cc.g, cc.b, b.Low ? 0.9f : 0.35f)); Fill(new Rect(br.xMax - 1, br.y, 1, br.height), new Color(cc.r, cc.g, cc.b, b.Low ? 0.9f : 0.35f));
                        cardCenter.fontSize = 11;
                        GUI.Label(br, "<color=" + Hex(b.Color) + ">" + RichSafe(b.Text) + "</color>", cardCenter);
                        break;
                    }
                    case "foot":
                        cardCenter.fontSize = 11;
                        GUI.Label(br, b.Parts != null ? RichParts(b.Parts) : "<color=" + Hex(b.Color) + ">" + RichSafe(b.Text) + "</color>", cardCenter);
                        break;
                }
            }
            cardCenter.fontSize = 12; cardSmall.fontSize = 10;
        }

        // ------------------------------------------------------------------------------------ rarity rings (live and HD-2D)
        Texture2D ringTex;

        Texture2D RingTexture()
        {
            using var _slow = SlowCalls.Scope("RingTexture", "load");
            if (ringTex != null) return ringTex;
            const int W = 64, H = 32;
            ringTex = new Texture2D(W, H, TextureFormat.RGBA32, false) { filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Clamp, name = "chaos-rarity-ring" };
            var px = new Color32[W * H];
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    float dx = (x + 0.5f - W / 2f) / (W / 2f), dy = (y + 0.5f - H / 2f) / (H / 2f);
                    float d = Mathf.Sqrt(dx * dx + dy * dy);
                    float ring = Mathf.Clamp01(1f - Mathf.Abs(d - 0.86f) / 0.1f);
                    float glow = Mathf.Clamp01(1f - Mathf.Abs(d - 0.86f) / 0.3f) * 0.35f;
                    px[y * W + x] = new Color32(255, 255, 255, (byte)(Mathf.Clamp01(ring + glow) * 255f));
                }
            ringTex.SetPixels32(px);
            ringTex.Apply(false, true);
            return ringTex;
        }

        /// <summary>The rarity ring under items lying near the player, in the live and HD-2D views (the classic view outlines the sprite itself).</summary>
        void DrawItemRings(Rect map, float scale)
        {
            using var _slow = SlowCalls.Scope("DrawItemRings", "OnGUI");
            if (!(LiveOn || (hd2d && hd2dView != null)) || !VisualPrefs.ItemOutlines || world?.Player == null || Event.current.type != EventType.Repaint) return;
            if (ItemGlowRealOn) return;   // phase 9 track D: the sprite shader draws the real outline; the ring is the fallback
            float tile = map.height / ViewTilesH;
            var me = world.Player.Position;
            double now = session != null ? session.Now : Time.realtimeSinceStartup * 1000.0;
            var tex = RingTexture();
            var old = GUI.color;
            int rx = Mathf.CeilToInt(ViewTilesW / 2f) + 1, ry = Mathf.CeilToInt(ViewTilesH / 2f) + 1;
            for (int dy = -ry; dy <= ry; dy++)
                for (int dx = -rx; dx <= rx; dx++)
                {
                    var p = new Pos(me.X + dx, me.Y + dy, me.Z);
                    var t = world.Get(p);
                    if (t == null || t.Things.Count == 0) continue;
                    var it = RarityGlow.Best(t.Things);
                    if (it == null) continue;
                    if (!TileScreenPx(p, out Vector3 px) || px.z < 0f) continue;
                    float x = px.x / scale - map.x, y = (UnityEngine.Screen.height - px.y) / scale - map.y;
                    if (x < -tile || x > map.width + tile || y < -tile || y > map.height + tile) continue;
                    var c = HexColor(RarityGlow.RingColor(it), Color.white);
                    float shimmer = RarityGlow.Shimmer(it, now);
                    c = Color.Lerp(c, new Color(1f, 0.96f, 0.8f), shimmer * 0.6f);
                    c.a = RarityGlow.Alpha(it, now);
                    var rr = RarityGlow.Ring(x, y, tile);
                    GUI.color = c;
                    GUI.DrawTexture(new Rect((float)rr.X, (float)rr.Y, (float)rr.W, (float)rr.H), tex, ScaleMode.StretchToFill, true);
                }
            GUI.color = old;
        }

        // ------------------------------------------------------------------------------------ top menu icons
        /// <summary>The 16 px icon of a menu entry or category (by its English text or category id) at r; false when the picture is not there.</summary>
        public bool DrawMenuIcon(string icon, Rect r, bool hover = false)
        {
            if (icon == null) return false;
            return DrawArt(TopMenuIcons.Path(icon, hover), r, true);
        }
    }
}
