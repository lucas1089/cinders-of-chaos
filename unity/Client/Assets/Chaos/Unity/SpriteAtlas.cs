// One 4096 x 4096 texture of 32 x 32 cells, filled on demand from the .spr file (and from composed outfit frames).
// Full: cleared and refilled (the view needs a few thousand cells at most).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class SpriteAtlas
    {
        public const int TextureSize = 4096, Cell = 32, PerRow = TextureSize / Cell;
        public readonly Texture2D Texture;
        readonly SprFile spr;
        readonly Dictionary<ulong, int> slots = new Dictionary<ulong, int>();
        readonly Color32[] scratch = new Color32[Cell * Cell];
        int next = 1;   // cell 0 stays transparent
        bool dirty;
        public int Generation;   // bumps when the atlas was cleared (cached UVs are stale)

        public SpriteAtlas(SprFile spr)
        {
            this.spr = spr;
            Texture = new Texture2D(TextureSize, TextureSize, TextureFormat.RGBA32, false)
            {
                filterMode = FilterMode.Point,
                wrapMode = TextureWrapMode.Clamp,
                name = "chaos-atlas"
            };
            Texture.SetPixels32(new Color32[TextureSize * TextureSize]);
            Texture.Apply(false);
        }

        /// <summary>The cell of a plain sprite; 0 (transparent) for an empty one.</summary>
        public int Sprite(uint id)
        {
            if (id == 0) return 0;
            ulong key = id;
            if (slots.TryGetValue(key, out int s)) return s;
            byte[] rgba;
            using (SlowCalls.Scope("SpriteAtlas.Sprite (spr read and decode)", "load")) rgba = spr.Rgba(id);   // the first sprite of a shard opens the shard (Core/SprShards.cs; a blob shard is decrypted whole, about 30 MB)
            s = rgba == null ? 0 : Put(rgba);
            slots[key] = s;
            return s;
        }

        /// <summary>The cell of a composed image (an outfit frame with its colours); `make` runs once per key.</summary>
        public int Composed(ulong key, System.Func<byte[]> make)
        {
            key |= 1UL << 63;
            if (slots.TryGetValue(key, out int s)) return s;
            byte[] rgba = make();
            s = rgba == null ? 0 : Put(rgba);
            slots[key] = s;
            return s;
        }

        public byte[] Raw(uint id) => spr.Rgba(id);

        int Put(byte[] rgba)
        {
            if (next >= PerRow * PerRow)
            {
                slots.Clear();
                next = 1;
                Generation++;
                Texture.SetPixels32(new Color32[TextureSize * TextureSize]);
            }
            int s = next++;
            int cx = s % PerRow * Cell, cy = s / PerRow * Cell;
            // the sprite's rows go top to bottom, the texture's bottom to top
            for (int y = 0; y < Cell; y++)
                for (int x = 0; x < Cell; x++)
                {
                    int i = (y * Cell + x) * 4;
                    scratch[(Cell - 1 - y) * Cell + x] = new Color32(rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]);
                }
            Texture.SetPixels32(cx, cy, Cell, Cell, scratch);
            dirty = true;
            return s;
        }

        /// <summary>Sends the texture to the GPU at most once a frame. Apply always sends the whole 64 MB; the effect, outfit and preview painters call this per new cell inside
        /// their loops, so a fresh character's first effects (kit, level up, gift, fireworks) sent it dozens of times in one frame: a 17 to 23 s frame under the CI player's
        /// software GL (PR 329 slow call log). A cell put after this frame's upload shows from the next frame.</summary>
        public void Upload()
        {
            if (!dirty) return;
            int frame = Time.frameCount;
            if (frame == appliedFrame) return;
            using var _slow = SlowCalls.Scope("SpriteAtlas.Upload (Apply of the 4096 x 4096 texture)", "upload");
            Texture.Apply(false);
            dirty = false;
            appliedFrame = frame;
            Uploads++;
        }

        int appliedFrame = -1;
        public int Uploads;   // how many times the texture went to the GPU (the live smoke reads it)

        public Rect Uv(int slot)
        {
            float u = slot % PerRow * Cell / (float)TextureSize, v = slot / PerRow * Cell / (float)TextureSize;
            float d = Cell / (float)TextureSize;
            return new Rect(u, v, d, d);
        }
    }
}
