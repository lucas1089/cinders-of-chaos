// The client guard (server src-patch 0021, server/README.md "Client guard"): the client sends the official identifier
// in the version field, then answers the server's challenge (extended opcode 189, "cg1:<32 hex>") with an HMAC under
// the client key, and says hello on opcode 190. The key is a build secret: the Unity build gets it from the
// environment (CHAOS_CLIENT_KEY, unity/README.md); without it the public development key is used, which only a test
// server with clientGuardAllowDevKey accepts.
using System;
using System.Security.Cryptography;
using System.Text;

namespace Chaos.Core
{
    public static class ClientGuard
    {
        public const ushort Tag = 0x4343;
        public const byte ChallengeOpcode = 189;
        public const byte HelloOpcode = 190;
        public static readonly byte[] DevKey = Encoding.ASCII.GetBytes("DEV-KEY-cinders-of-chaos-UNSAFE!");

        /// <summary>The u32 client version the guard expects: the tag in the high half, the build in the low half.</summary>
        public static uint Identifier(ushort build) => (uint)Tag << 16 | build;

        /// <summary>HMAC-SHA256(key, nonce || u16 #account || account || u16 #character || character || u16 build)</summary>
        public static byte[] Mac(byte[] key, byte[] nonce, string account, string character, ushort build)
        {
            var w = new ByteWriter().Raw(nonce).Str(account).Str(character).U16(build);
            using (var h = new HMACSHA256(key)) return h.ComputeHash(w.ToArray());
        }

        /// <summary>The nonce of a challenge text ("cg1:" + 32 hex digits), or null.</summary>
        public static byte[] ParseChallenge(string text)
        {
            if (text == null || !text.StartsWith("cg1:") || text.Length != 36) return null;
            var nonce = new byte[16];
            for (int i = 0; i < 16; i++)
            {
                if (!byte.TryParse(text.Substring(4 + 2 * i, 2), System.Globalization.NumberStyles.HexNumber, null, out nonce[i])) return null;
            }
            return nonce;
        }

        public static string Answer(byte[] key, byte[] nonce, string account, string character, ushort build)
        {
            var sb = new StringBuilder("cg1:" + build + ":");
            foreach (byte b in Mac(key, nonce, account, character, build)) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }

        public static string Hello(ushort build) => "{\"action\":\"hello\",\"data\":{\"build\":" + build + ",\"modules\":99}}";
    }
}
