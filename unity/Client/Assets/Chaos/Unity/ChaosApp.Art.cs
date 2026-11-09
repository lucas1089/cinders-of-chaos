// Art of the main client's modules in the Unity HUD (O433 phase 6, track U): spell icons (spellbook, hotbar), buff icons, toast icons, the health and mana
// globes and the monster bar frame. The pictures are the main client's own files, read from the overlay folders like the sounds (OverlayPath; CI copies the
// module folders into StreamingAssets/overlay/modules and the data pictures into StreamingAssets/overlay/data, unity-prototype.yml). The rules for which file and
// which part are in Core/OverlayArt.cs. Every drawing has the older stand-in (a coloured square with text, plain bars): a missing file never breaks a window.
using System.Collections.Generic;
using System.IO;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        readonly Dictionary<string, Texture2D> artTex = new Dictionary<string, Texture2D>();
        bool artWarned;

        /// <summary>A picture of the overlay folders (pixel art unsmoothed unless smooth), null when no folder has it. Cached, a missing file too.</summary>
        public Texture2D ArtTexture(string rel, bool smooth = false)
        {
            string key = (smooth ? "s|" : "p|") + rel;
            if (artTex.TryGetValue(key, out var t)) return t;
            t = null;
            using var _slow = SlowCalls.Scope(SlowCalls.Log.On ? "ArtTexture " + rel : null, "load");   // the first read of a picture of the overlay folders (Core/SlowCalls.cs)
            string path = OverlayPath(rel);
            if (path != null)
            {
                try
                {
                    t = new Texture2D(2, 2, TextureFormat.RGBA32, false) { filterMode = smooth ? FilterMode.Bilinear : FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
                    if (!t.LoadImage(File.ReadAllBytes(path))) { Destroy(t); t = null; }
                }
                catch (System.Exception) { t = null; }
            }
            else if (!artWarned)
            {
                artWarned = true;
                Debug.Log("chaos art: no " + rel + " in " + string.Join(", ", OverlayRoots()) + " (set " + OverlayFiles.EnvVar + "; the icons stay text)");
            }
            artTex[key] = t;
            return t;
        }

        /// <summary>True when the spell icon sheet is there, so a window can say it has no icons.</summary>
        public bool HasSpellIcons => ArtTexture(SpellIcons.Path(SpellIcons.Sheet32)) != null;

        /// <summary>The icon of a spell (a cell of the 32 px sheet) into r; false when the spell has none or the sheet is missing (a stock spell, no files).</summary>
        public bool DrawSpellIcon(Rect r, string words, int spellId)
        {
            int cell = SpellIcons.Cell(words, spellId);
            if (cell == 0) return false;
            var painted = PaintedSpellTexture(cell);   // phase 8 track A: the "Painted icons" option
            if (painted != null) { GUI.DrawTexture(r, painted, ScaleMode.StretchToFill, true); return true; }
            var tex = ArtTexture(SpellIcons.Path(SpellIcons.Sheet32));
            if (tex == null || !SpellIcons.CellUv(cell, 32, 32, tex.width, tex.height, out float u, out float v, out float w, out float h)) return false;
            GUI.DrawTextureWithTexCoords(r, tex, new Rect(u, v, w, h));
            return true;
        }

        /// <summary>The icon of a spell list entry: its cell, or the sprite of the rune it conjures; false for neither.</summary>
        public bool DrawSpellEntryIcon(Rect r, Spell sp)
        {
            if (sp == null) return false;
            if (DrawSpellIcon(r, sp.Words, sp.Id)) return true;
            if (sp.IsRune && sp.RuneClientId > 0 && dat?.Item((ushort)sp.RuneClientId) != null) { DrawItem(r, (ushort)sp.RuneClientId, 0); return true; }
            return false;
        }

        /// <summary>A buff's icon (its own 26 px picture) into r; false when its file is missing.</summary>
        public bool DrawBuffIcon(Rect r, BuffEntry b)
        {
            var tex = BuffTexture(b);
            if (tex == null) return false;
            GUI.DrawTexture(r, tex, ScaleMode.StretchToFill, true);
            return true;
        }

        public Texture2D BuffTexture(BuffEntry b)
        {
            if (b == null) return null;
            string name = BuffIcons.OwnName(b.Icon, b.Key);
            return PaintedBuffTexture(name) ?? ArtTexture(BuffIcons.Path(name));
        }

        /// <summary>The icon of a toast type, 48 px, into r; false when its file is missing.</summary>
        public bool DrawToastIcon(Rect r, string type)
        {
            var tex = ArtTexture(ToastIcons.Path(type));
            if (tex == null) return false;
            GUI.DrawTexture(r, tex, ScaleMode.StretchToFill, true);
            return true;
        }

        /// <summary>A picture drawn as a nine-slice: corners as they are, edges and middle stretched (the plates of the monster bar).</summary>
        public static void DrawNineSlice(Rect r, Texture2D t, int bx, int by)
        {
            if (t == null) return;
            float tw = t.width, th = t.height;
            float x0 = r.x, x1 = r.x + bx, x2 = r.xMax - bx, y0 = r.y, y1 = r.y + by, y2 = r.yMax - by;
            float u1 = bx / tw, u2 = 1f - bx / tw, vb = by / th, vt = 1f - by / th;
            void Part(float x, float y, float w, float h, float u, float v, float uw, float vh)
            {
                if (w <= 0 || h <= 0) return;
                GUI.DrawTextureWithTexCoords(new Rect(x, y, w, h), t, new Rect(u, v, uw, vh));
            }
            // texture coordinates run from the bottom: the top row of the screen is the top band of the picture
            Part(x0, y0, bx, by, 0, vt, u1, vb); Part(x1, y0, x2 - x1, by, u1, vt, u2 - u1, vb); Part(x2, y0, bx, by, u2, vt, u1, vb);
            Part(x0, y1, bx, y2 - y1, 0, vb, u1, vt - vb); Part(x1, y1, x2 - x1, y2 - y1, u1, vb, u2 - u1, vt - vb); Part(x2, y1, bx, y2 - y1, u2, vb, u1, vt - vb);
            Part(x0, y2, bx, by, 0, 0, u1, vb); Part(x1, y2, x2 - x1, by, u1, 0, u2 - u1, vb); Part(x2, y2, bx, by, u2, 0, u1, vb);
        }


        // ------------------------------------------------------------------------------------ the hotbar's items
        /// <summary>True for an item the main client uses with a crosshair (a rune, a potion, a tool): the default mode of its hotbar slot.</summary>
        public bool ItemIsMultiUse(int clientId) => dat?.Item((ushort)clientId)?.MultiUse ?? false;

        /// <summary>The item menu's "Add to hotbar": the item goes to the first empty slot of the hotkey bar.</summary>
        public void AddToHotbar(ItemRef r)
        {
            if (r.Item == null) return;
            var bar = FindWindow<HotkeyBarWindow>();
            int slot = bar != null ? bar.AddItem(r.Id, ItemIsMultiUse(r.Id)) : -1;
            PostLine(slot >= 0 ? Loc.T("Added to hotbar slot {0}.", HotbarLayout.KeyLabel(slot)) : Loc.T("The hotbar is full."));
        }


        // ------------------------------------------------------------------------------------ the monster bar
        /// <summary>The monster bar with the art of game_monsterbar: the frame over the health fill and the damage trail, name and level plates, modifier chips.
        /// Returns the bottom of the panel, or -1 when a picture is missing (the caller draws the plain bar).</summary>
        float HudMonsterBarArt(HudState hud, Creature c, MonsterInfo info, string key, (string name, string label, string world, bool role) style, float w, float top, double now, float scale)
        {
            var frame = ArtTexture(MonsterBarArt.Frame(key));
            var fill = ArtTexture(MonsterBarArt.Fill(key));
            var plaque = ArtTexture(MonsterBarArt.Plaque(key));
            if (frame == null || fill == null || plaque == null) return -1f;
            var trail = ArtTexture(MonsterBarArt.Trail);
            float px = Mathf.Floor(w / 2f - MonsterBarArt.PanelW / 2f), py = top;
            uiRects.Add(Scaled(new Rect(px, py, MonsterBarArt.PanelW, MonsterBarArt.PanelH), scale));
            var socket = new Rect(px + MonsterBarArt.SocketX, py + MonsterBarArt.SocketY, MonsterBarArt.SocketW, MonsterBarArt.SocketH);
            Fill(socket, new Color(0.055f, 0.039f, 0.047f, 1f));
            int tw = MonsterBar.FillWidth(hud.Monster.TrailValue, MonsterBarArt.SocketW), fw = MonsterBar.FillWidth(hud.Monster.Percent, MonsterBarArt.SocketW);
            if (trail != null && tw > 0) GUI.DrawTextureWithTexCoords(new Rect(socket.x, socket.y, tw, socket.height), trail, new Rect(0f, 0f, (float)tw / MonsterBarArt.SocketW, 1f));
            if (fw > 0) GUI.DrawTextureWithTexCoords(new Rect(socket.x, socket.y, fw, socket.height), fill, new Rect(0f, 0f, (float)fw / MonsterBarArt.SocketW, 1f));
            GUI.DrawTexture(new Rect(px, py + MonsterBarArt.FrameY, MonsterBarArt.PanelW, MonsterBarArt.FrameH), frame, ScaleMode.StretchToFill, true);

            var ps = new GUIStyle(small) { fontSize = 11, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            ps.normal.textColor = HexColor("#f4ead2", Color.white);
            string pct = MonsterBar.PercentText(hud.Monster.Percent);
            float pw = ps.CalcSize(new GUIContent(pct)).x + 6f;
            var pr = new Rect(socket.center.x - pw / 2f, socket.center.y - 7f, pw, 14f);
            Fill(pr, new Color(0.047f, 0.031f, 0.039f, 0.7f));
            GUI.Label(pr, pct, ps);

            Color nameCol = HexColor(style.name, Color.white);
            var ns = new GUIStyle(small) { fontSize = 12, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter, clipping = TextClipping.Clip };
            ns.normal.textColor = nameCol;
            // a long title drops its tag (the frame tells the tier)
            string title = MonsterBar.Title(key, info?.Label ?? "", c.Name);
            if (ns.CalcSize(new GUIContent(title)).x > MonsterBarArt.NameMax - MonsterBarArt.PlatePad) title = c.Name;
            int nameW = MonsterBarArt.PlateWidth(ns.CalcSize(new GUIContent(title)).x, MonsterBarArt.NameMin, MonsterBarArt.NameMax);
            var plate = new Rect(px + Mathf.Floor((MonsterBarArt.PanelW - nameW) / 2f), py + MonsterBarArt.PlateTop, nameW, MonsterBarArt.PlateH);
            DrawNineSlice(plate, plaque, MonsterBarArt.PlateBorderX, MonsterBarArt.PlateBorderY);
            GUI.Label(plate, title, ns);
            // no level plate left of the name: the name already ends in the level ("Rat [2]"), as in the main client

            // modifier chips under the frame, centred, with their tooltips
            if (info != null && info.Mods.Count > 0)
            {
                int n = info.Mods.Count;
                float x0 = px + Mathf.Floor((MonsterBarArt.PanelW - MonsterBarArt.ChipsWidth(n)) / 2f), cy = py + MonsterBarArt.ModsTop;
                string tip = null;
                Rect tipAt = default;
                var e = Event.current;
                for (int i = 0; i < n; i++)
                {
                    var chip = new Rect(x0 + i * (MonsterBarArt.ChipSize + MonsterBarArt.ChipSpacing), cy, MonsterBarArt.ChipSize, MonsterBarArt.ChipSize);
                    string nm = info.Mods[i];
                    var ct = ArtTexture(MonsterBarArt.Chip(nm));
                    if (ct != null) GUI.DrawTexture(chip, ct, ScaleMode.StretchToFill, true);
                    else
                    {
                        Fill(chip, new Color(0.25f, 0.12f, 0.12f, 0.95f));
                        GUI.Label(chip, nm.Length > 0 ? nm.Substring(0, 1).ToUpperInvariant() : "?", hudTiny);
                    }
                    if (chip.Contains(e.mousePosition)) { tip = nm + ": " + MonsterBar.ModTip(nm); tipAt = chip; }
                }
                if (tip != null)
                {
                    var tr = new Rect(Mathf.Min(tipAt.x, w - 308f), tipAt.yMax + 4f, 300, 36);
                    Fill(tr, new Color(0.03f, 0.02f, 0.04f, 0.95f));
                    GUI.Label(new Rect(tr.x + 4, tr.y + 2, tr.width - 8, tr.height - 4), tip, toastText);
                }
            }
            return py + MonsterBarArt.PanelH;
        }

        // ------------------------------------------------------------------------------------ the globes
        const int GlobeSize = 96;
        const int GlobeArtSize = 76;

        /// <summary>One globe: a dark well, the tinted liquid cut to the fill from the bottom, the painted ring over it and the number (game_shaderfx plain globe).</summary>
        void DrawGlobe(Rect r, Texture2D ring, Texture2D mask, double fill, Color tint, int value)
        {
            int liquid = OrbArt.Liquid(GlobeSize);
            int texels = mask.width;
            float margin = Mathf.Floor((GlobeSize - liquid) / 2f);
            OrbArt.PlainClip(fill, texels, liquid, out int clip, out int drawnH);
            var well = new Rect(r.x + margin, r.y + GlobeSize - margin - liquid, liquid, liquid);
            var old = GUI.color;
            GUI.color = new Color(0.04f, 0.02f, 0.04f, 0.85f);
            GUI.DrawTexture(well, mask, ScaleMode.StretchToFill, true);
            if (drawnH > 0 && clip > 0)
            {
                GUI.color = tint;
                var fillRect = new Rect(well.x, well.yMax - drawnH, liquid, drawnH);
                GUI.DrawTextureWithTexCoords(fillRect, mask, new Rect(0, 0, 1, (float)clip / texels));
            }
            GUI.color = old;
            GUI.DrawTexture(r, ring, ScaleMode.StretchToFill, true);
            var st = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = 14, fontStyle = FontStyle.Bold };
            st.normal.textColor = Color.black;
            string text = OrbArt.Short(value);
            GUI.Label(new Rect(r.x + 1, r.y + 1, r.width, r.height), text, st);
            st.normal.textColor = Color.white;
            GUI.Label(r, text, st);
        }

        /// <summary>The health and mana globes beside the hotkey bar (or at the bottom centre while it is closed). Drawn only when the ring and mask pictures are there and the option is on.</summary>
        void HudGlobes(float w, float h, float scale)
        {
            if (!VisualPrefs.Globes) return;
            var p = session?.Parser;
            if (p == null) return;
            var ring = ArtTexture(OrbArt.RingFile(GlobeArtSize), true);
            var mask = ArtTexture(OrbArt.MaskFile(GlobeArtSize), true);
            if (ring == null || mask == null) return;
            var bar = FindWindow<HotkeyBarWindow>();
            var a = bar != null && bar.Open ? bar.Area : new Rect(w / 2f - 220f, h - 110f, 440f, 102f);
            // on top of the bar, in from its ends: beside it they hid under the chat and the Fight window
            float y = Mathf.Max(0f, a.y - GlobeSize - 2f);
            float hx = Mathf.Max(0f, a.x + 24f), mx = Mathf.Min(w - GlobeSize, a.xMax - GlobeSize - 24f);
            if (hx + GlobeSize > mx) hx = Mathf.Max(0f, mx - GlobeSize - 4f);
            var hr = new Rect(hx, y, GlobeSize, GlobeSize);
            var mr = new Rect(mx, y, GlobeSize, GlobeSize);
            uiRects.Add(Scaled(hr, scale));
            uiRects.Add(Scaled(mr, scale));
            DrawGlobe(hr, ring, mask, OrbArt.Fill(p.Health, p.MaxHealth), HexColor(OrbArt.HealthColor, Color.red), p.Health);
            DrawGlobe(mr, ring, mask, OrbArt.Fill(p.Mana, p.MaxMana), HexColor(OrbArt.ManaColor, Color.blue), p.Mana);
        }
    }
}
