// Phase 7, track Y (P1 systems): the glue of the monster bar's world side (tier colour and modifier lines over the head, oversized monsters, bosses bigger),
// the bitmap fonts of the main client (damage numbers by type), the toast art (plate, answer buttons, the monster look), the store's look icons and
// the Inspect Player button that shows another character's passive tree. The rules are Core/Phase7Y.cs, Core/Phase7YTree.cs.
using System;
using System.Collections.Generic;
using System.IO;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>The bitmap fonts of client/overlay/data/fonts/chaos (the .otfont text and its sheet), read once from the overlay folders; null when a file is missing.</summary>
    public static class Phase7YFonts
    {
        /// <summary>Set by the app: a file of the overlay folders by its path under "modules".</summary>
        public static Func<string, string> Path = rel => null;
        static readonly Dictionary<string, BitmapFont> cache = new Dictionary<string, BitmapFont>();

        public static BitmapFont Get(string name)
        {
            if (string.IsNullOrEmpty(name)) return null;
            BitmapFont f;
            if (cache.TryGetValue(name, out f)) return f;
            f = null;
            using var _slow = SlowCalls.Scope("Phase7YFonts.Get " + name, "load");
            try
            {
                string def = Path(ScatterFonts.DefPath(name)), sheet = Path(ScatterFonts.SheetPath(name));
                if (def != null && sheet != null)
                {
                    f = BitmapFont.ParseDef(File.ReadAllText(def));
                    var tex = new Texture2D(2, 2, TextureFormat.RGBA32, false);
                    if (f != null && tex.LoadImage(File.ReadAllBytes(sheet)))
                    {
                        // GetPixels32 runs bottom row first, the font wants the top row first
                        var px = tex.GetPixels32();
                        int w = tex.width, h = tex.height;
                        var rgba = new byte[w * h * 4];
                        for (int y = 0; y < h; y++)
                            for (int x = 0; x < w; x++)
                            {
                                var c = px[(h - 1 - y) * w + x];
                                int i = (y * w + x) * 4;
                                rgba[i] = c.r; rgba[i + 1] = c.g; rgba[i + 2] = c.b; rgba[i + 3] = c.a;
                            }
                        f.SetSheet(rgba, w, h);
                        if (!f.Ready) f = null;
                    }
                    else f = null;
                    UnityEngine.Object.Destroy(tex);
                }
            }
            catch (Exception) { f = null; }
            cache[name] = f;
            return f;
        }
    }

    public sealed partial class ChaosApp
    {
        readonly Dictionary<int, BodyBox> bodyBoxes = new Dictionary<int, BodyBox>();
        double monsterAskAt = -1e9;

        /// <summary>Every frame: the hooks of this track into the map view and the fonts.</summary>
        void Phase7YUpdate()
        {
            using var _slow = SlowCalls.Scope("Phase7YUpdate", "Update");
            Phase7YFonts.Path = OverlayPath;
            Phase8AUpdate();   // ChaosApp.Phase8A.cs
            var inspect = session?.Social?.Inspect;
            if (inspect != null) inspect.ViewTree = ViewOtherTree;
            if (view != null)
            {
                view.CreatureScale = MonsterScaleFor;
                view.ItemOutlines = VisualPrefs.ItemOutlines;
            }
        }

        /// <summary>The opaque bounds of a look's body: the first idle frame, facing south, every sprite of the group placed as drawn (monsterbarmath.lua bodySize from the outfit anchors).</summary>
        BodyBox BodyBoxOf(int look)
        {
            BodyBox b;
            if (bodyBoxes.TryGetValue(look, out b)) return b;
            b = BodyBox.None;
            var t = world?.Dat?.Outfit(look);
            if (t != null && atlas != null)
            {
                var g = t.Idle;
                int dir = Mathf.Min((int)Dir.South, g.PatternX - 1);
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                    {
                        uint id = g.Sprite(ww, hh, 0, dir, 0, 0, 0);
                        if (id != 0) b.Add(atlas.Raw(id), 32, 32, (g.Width - 1 - ww) * 32, (g.Height - 1 - hh) * 32);
                    }
            }
            bodyBoxes[look] = b;
            return b;
        }

        /// <summary>The draw size of a monster (MonsterWorld.DrawScale): bosses and omens bigger, an oversized monster smaller until the server says what it is.</summary>
        float MonsterScaleFor(Creature c)
        {
            if (c == null || c.Type != 1 || c.Outfit.LookType == 0 || session == null) return 1f;
            var info = session.Hud.Monster.Info(c.Id);
            var box = BodyBoxOf(c.Outfit.LookType);
            float s = MonsterWorld.DrawScale(box, info?.Tier, info?.Role);
            // a body too big for an ordinary monster: ask for the tier at once, so a boss is never left shrunk (one question each 250 ms, once per 30 s per creature)
            if (info == null && s < 1f && session.Now - monsterAskAt >= 250)
            {
                monsterAskAt = session.Now;
                session.Hud.Monster.Query(c.Id, session.Now);
            }
            return s;
        }

        /// <summary>The name colour of a tiered monster, else the colour it had.</summary>
        Color MonsterNameColor(Creature c, Color col)
        {
            if (c == null || c.Type != 1 || session == null) return col;
            string hex = MonsterWorld.NameColor(session.Hud.Monster.Info(c.Id));
            Color t;
            return hex != null && ColorUtility.TryParseHtmlString(hex, out t) ? t : col;
        }

        /// <summary>The tier word and the modifier lines above a tiered monster's name (monsterbar.lua labelCreature): two modifiers to a line.</summary>
        void DrawMonsterMods(Creature c, float x, Rect nameRect)
        {
            if (c == null || c.Type != 1 || session == null || Event.current.type != EventType.Repaint) return;
            var info = session.Hud.Monster.Info(c.Id);
            string col = MonsterWorld.NameColor(info);
            if (info == null || col == null) return;
            var lines = MonsterWorld.ModLines(info.Mods);
            string word = MonsterWorld.TierWord(info);
            if (word.Length > 0) lines.Insert(0, Loc.T(word));
            if (lines.Count == 0) return;
            var st = worldTiny ?? nameStyle;
            for (int i = 0; i < lines.Count; i++)
                ShadowText(new Rect(x - 110, nameRect.y - 13 * (lines.Count - i), 220, 14), lines[i], st, HexColor(col));
        }

        // ------------------------------------------------------------------------------------ toast art
        /// <summary>The toast plate (game_chaosnotify Background, tinted) behind a toast; false when the picture is missing.</summary>
        bool DrawToastPlate(Rect box)
        {
            var tex = ArtTexture(ToastArt.Plate, true);
            if (tex == null) return false;
            var old = GUI.color;
            GUI.color = HexColor(ToastArt.PlateTint);
            GUI.DrawTexture(box, tex, ScaleMode.StretchToFill);
            GUI.color = old;
            return true;
        }

        /// <summary>An answer button of the invitation toasts from its four state strip; label drawn over it. Returns true on a click, false when the strip is missing (the caller draws the stock button).</summary>
        bool DrawToastButton(Rect r, string label, bool accept, bool enabled, out bool clicked)
        {
            clicked = false;
            var tex = ArtTexture(accept ? ToastArt.AcceptStrip : ToastArt.DeclineStrip);
            if (tex == null) return false;
            var e = Event.current;
            bool over = enabled && r.Contains(e.mousePosition);
            bool down = over && Input.GetMouseButton(0);
            var state = ToastArt.StateOf(enabled, over, down);
            float h = tex.height > 0 ? tex.height : ToastArt.ButtonH * 4;
            if (e.type == EventType.Repaint)
            {
                GUI.DrawTextureWithTexCoords(r, tex, new Rect(0f, 1f - (ToastArt.ClipY(state) + ToastArt.ButtonH) / h, 1f, ToastArt.ButtonH / h));
                var st = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = 12 };
                st.normal.textColor = HexColor(ToastArt.LabelColor(state));
                GUI.Label(new Rect(r.x + (state == ToastArt.ButtonState.Pressed ? 1 : 0), r.y + (state == ToastArt.ButtonState.Pressed ? 1 : 0), r.width, r.height), label, st);
            }
            if (over && e.type == EventType.MouseUp && e.button == 0) { clicked = true; e.Use(); }
            return true;
        }

        /// <summary>The creature a task, bounty, bestiary or battle pass toast is about, over the icon (the main client's UICreature).</summary>
        void DrawToastMonster(Rect iconRect, Toast t)
        {
            if (!ToastArt.HasMonsterLook(t) || Event.current.type != EventType.Repaint) return;
            DrawOutfit(new Rect(iconRect.x, iconRect.y, ToastArt.MonsterBox, ToastArt.MonsterBox), new Outfit { LookType = t.MonsterLook });
        }

        // ------------------------------------------------------------------------------------ store look icons
        /// <summary>The icon of an offer whose look is a picture or a colour sample; false for a native icon (an item or a creature). pic is the 56 px cell.</summary>
        public bool DrawStoreLook(Rect pic, StoreLookIcon look)
        {
            if (look == null || look.Mode == StoreLookIcon.Native) return false;
            if (look.Mode == StoreLookIcon.Image)
            {
                var tex = ArtTexture(look.Path);
                if (tex == null) return false;
                float w = tex.width, h = tex.height;
                float k = Mathf.Min((pic.width - 4) / Mathf.Max(1f, w), (pic.height - 4) / Mathf.Max(1f, h));
                var r = new Rect(pic.center.x - w * k / 2f, pic.center.y - h * k / 2f, w * k, h * k);
                GUI.DrawTexture(r, tex, ScaleMode.StretchToFill);
                return true;
            }
            Color c;
            if (!ColorUtility.TryParseHtmlString(look.Color, out c)) return false;
            if (look.Accent) Fill(new Rect(pic.x + 4, pic.center.y - 8, pic.width - 8, 16), c);
            else
            {
                var st = new GUIStyle(titleStyle) { alignment = TextAnchor.MiddleCenter, fontSize = 22 };
                st.normal.textColor = c;
                GUI.Label(pic, StoreLookIcon.SampleText(look), st);
            }
            return true;
        }

        // ------------------------------------------------------------------------------------ inspect: another character's tree
        /// <summary>Shows the inspected character's passive tree, read-only, in the tree window.</summary>
        public void ViewOtherTree(object data)
        {
            var tree = session?.Progress?.Tree;
            var w = FindWindow<PassiveTreeWindow>();
            if (tree == null || w == null || !tree.ShowOther(data)) return;
            w.Open = true;
        }
    }
}
