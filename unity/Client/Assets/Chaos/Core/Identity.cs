// Who the Unity client says it is to the server (docs: unity/README.md "Both clients", docs/UNITY_PARITY.md).
//
// The server gates on three things (server/src-patches, read 2026-11-07):
//   1. The OS word of both login packets. ProtocolGame::login turns extended opcodes on for `operatingSystem >=
//      CLIENTOS_OTCLIENT_LINUX` (10) or an OTCv8 marker; the client guard (0021) refuses an OS below 10; Player::
//      sendEnergyShield and the Lua senders (Player:sendExtendedOpcode) do the same test. Protocol.Os is 21, so the
//      Unity client has always been an extended-opcode client. server/tools/loadtest.py proves it: OS 10, no markers,
//      and the Chaos modules talk to the bots.
//   2. The markers after the random byte of the game login (the main client sends them, the load test does not):
//      u16 5 "OTCv8", u16 version, "OTCv8TierByte", "A", u32 signature, "C", u8 capabilities.
//      Any OTCv8 version makes `otclientV8` non-zero: sendFeatures (0x43 feature list), outfits with wings, aura and
//      shader, floors as 0x4B messages. "OTCv8TierByte" + "A" make `chaosClient`: item custom attributes (feature
//      126), packet compression when config.lua packetCompression is on, and the capabilities byte is read: bit 7
//      typed impact numbers (0051, feature 155), bit 6 16-bit spell ids (0079, feature 152, only when the server has
//      chaosWideSpellIds = true).
//   3. The u32 client version of both login packets: 0x4343 << 16 | build (ClientGuard.Identifier).
// Identity.Extended keeps the plain 10.98 wire (markers u16 0). Identity.Chaos sends all the markers; the parser
// (GameParser, GameSession) reads what that turns on.
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class ClientIdentity
    {
        /// <summary>CLIENTOS_OTCLIENTV8_WINDOWS. Any value from 10 up is "an extended opcode client" to the engine.</summary>
        public ushort Os = Protocol.Os;
        /// <summary>Send the OTCv8 markers (feature list, extended outfits, 0x4B floors, item attributes).</summary>
        public bool Markers;
        /// <summary>The OTCv8 version of the markers (253, 260, 261 ... the engine only tests it for non-zero).</summary>
        public ushort V8Version = 261;
        /// <summary>The u32 after "A": the engine skips it.</summary>
        public uint Signature;
        /// <summary>Bit 6 wide spell ids, bit 7 typed impact numbers (GameParser.TextMessage reads the three extra fields; DamageScatter.cs). Only set a bit when the parser reads what it turns on.</summary>
        public byte Capabilities = CapWideSpellIds | CapImpactText;

        public const byte CapWideSpellIds = 1 << 6;
        public const byte CapImpactText = 1 << 7;

        /// <summary>Markers u16 0: the plain 10.98 wire, extended opcodes only. What the prototype always did.</summary>
        public static ClientIdentity Extended => new ClientIdentity();

        /// <summary>All markers: the same wire as the main client.</summary>
        public static ClientIdentity Chaos(ushort build) => new ClientIdentity { Markers = true, Signature = build };

        /// <summary>The marker bytes of the game login (after the random byte, inside the RSA block).</summary>
        public void WriteMarkers(ByteWriter w)
        {
            if (!Markers) { w.U16(0); return; }
            w.Str("OTCv8").U16(V8Version).Str("OTCv8TierByte").Str("A").U32(Signature).Str("C").U8(Capabilities);
        }

        /// <summary>The identity named by a text ("extended" or "chaos"), for a setting or an environment variable.</summary>
        public static ClientIdentity Parse(string text, ushort build)
        {
            string t = (text ?? "").Trim().ToLowerInvariant();
            if (t == "chaos" || t == "full" || t == "v8") return Chaos(build);
            return Extended;
        }
    }

    /// <summary>The feature list of the 0x43 packet (u16 count, then u8 feature and u8 enabled each). Numbers are the
    /// engine's GameFeature values; only the Chaos ones are named, the rest are plain numbers.</summary>
    public sealed class ClientFeatures
    {
        public const int ItemCustomAttributes = 126;
        public const int ExtendedSpellIds = 152;
        public const int ImpactText = 155;

        readonly HashSet<int> on = new HashSet<int>();
        /// <summary>True once a 0x43 packet arrived (the server knows us as an OTCv8 client).</summary>
        public bool Announced { get; private set; }

        public bool Has(int feature) => on.Contains(feature);
        public IEnumerable<int> All => on;

        public void Set(int feature, bool enabled)
        {
            if (enabled) on.Add(feature); else on.Remove(feature);
        }

        /// <summary>Reads the body of a 0x43 packet (after the opcode).</summary>
        public void Read(ByteReader r)
        {
            Announced = true;
            for (int n = r.U16(), i = 0; i < n; i++)
            {
                int feature = r.U8();
                Set(feature, r.U8() != 0);
            }
        }

        public void Clear() { on.Clear(); Announced = false; }
    }
}
