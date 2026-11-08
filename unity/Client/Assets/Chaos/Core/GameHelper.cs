// The helper's hands on a real game session: IHelperHost over a GameSession (see HelperEngine.cs), and the packet to drink a potion.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class HelperPackets
    {
        /// <summary>Use an item on a creature: 0x84, the item's position, its id, its stack position, the creature id. A potion on yourself.</summary>
        public static byte[] UseWithCreature(Pos from, ushort id, byte stackPos, uint creature) =>
            new ByteWriter().U8(0x84).U16((ushort)from.X).U16((ushort)from.Y).U8((byte)from.Z).U16(id).U8(stackPos).U32(creature).ToArray();
    }

    public sealed partial class GameSession
    {
        /// <summary>Uses an item (a client id) from the equipment or an open bag on a creature (0x84). False when no such item is at hand.</summary>
        public bool UseItemOnCreature(int clientId, uint creature)
        {
            if (conn == null) return false;
            for (int slot = 1; slot < parser.Inventory.Length; slot++)
            {
                var it = parser.Inventory[slot];
                if (it != null && it.Id == clientId) { conn.Send(HelperPackets.UseWithCreature(InventoryPos(slot), (ushort)clientId, 0, creature)); return true; }
            }
            foreach (var kv in parser.Containers)
            {
                var c = kv.Value;
                for (int i = 0; i < c.Items.Count; i++)
                {
                    if (c.Items[i] == null || c.Items[i].Id != clientId) continue;
                    int slot = c.FirstIndex + i;
                    conn.Send(HelperPackets.UseWithCreature(ContainerPos(c.Id, slot), (ushort)clientId, (byte)slot, creature));
                    return true;
                }
            }
            return false;
        }

        /// <summary>Uses a carried item by itself (0x82: food) from the equipment or an open bag. False when no such item is at hand.</summary>
        public bool UseCarriedItem(int clientId)
        {
            if (conn == null) return false;
            for (int slot = 1; slot < parser.Inventory.Length; slot++)
            {
                var it = parser.Inventory[slot];
                if (it != null && it.Id == clientId) { UseItem(InventoryPos(slot), (ushort)clientId, 0); return true; }
            }
            foreach (var kv in parser.Containers)
            {
                var c = kv.Value;
                for (int i = 0; i < c.Items.Count; i++)
                {
                    if (c.Items[i] == null || c.Items[i].Id != clientId) continue;
                    int slot = c.FirstIndex + i;
                    UseItem(ContainerPos(c.Id, slot), (ushort)clientId, (byte)slot, (byte)c.Id);
                    return true;
                }
            }
            return false;
        }

        /// <summary>How many of the item are in the equipment and the open bags (a non-stackable item counts one each).</summary>
        public int CountItem(int clientId)
        {
            int n = 0;
            for (int slot = 1; slot < parser.Inventory.Length; slot++)
            {
                var it = parser.Inventory[slot];
                if (it != null && it.Id == clientId) n += Math.Max(1, it.Count);
            }
            foreach (var c in parser.Containers.Values)
                foreach (var it in c.Items) if (it != null && it.Id == clientId) n += Math.Max(1, it.Count);
            return n;
        }
    }

    /// <summary>IHelperHost over a GameSession: the stats, the creatures around and the actions of the main client's helper.</summary>
    public sealed class SessionHelperHost : IHelperHost, IHelperHostExt
    {
        public const int StateHaste = 64, StateProtectionZone = 16384;
        readonly GameSession s;
        int lastPackets = -1;
        double lastReadAt;

        public SessionHelperHost(GameSession session) { s = session; lastReadAt = session.Now; }

        GameParser P => s.Parser;
        public double Now => s.Now;
        public int Health => P.Health;
        public int MaxHealth => P.MaxHealth;
        public int Mana => P.Mana;
        public int MaxMana => P.MaxMana;
        public int Level => P.Level;
        public Pos Position { get { var me = P.W.Player; return me != null ? me.Position : default(Pos); } }
        public Dir Facing { get { var me = P.W.Player; return me != null ? me.Direction : Dir.South; } }
        public bool InProtectionZone => (P.PlayerStates & StateProtectionZone) != 0;
        public bool Hasted => (P.PlayerStates & StateHaste) != 0;
        public uint AttackTarget => s.AttackTarget;
        public bool Following => false;   // the Unity client has no follow state yet (GameSession.Follow clears the attack)

        public double MsSinceLastRead
        {
            get
            {
                if (s.Packets != lastPackets) { lastPackets = s.Packets; lastReadAt = s.Now; }
                return s.Now - lastReadAt;
            }
        }

        public IList<HelperCreature> Monsters()
        {
            var o = new List<HelperCreature>();
            foreach (var c in P.W.Creatures.Values)
            {
                if (c.Type != 1 || c.HealthPercent <= 0) continue;   // monsters only: not players, NPCs or summons
                string n = c.Name.ToLowerInvariant();
                if (n.Contains("effigy") || n.Contains("decoy")) continue;
                o.Add(new HelperCreature(c.Id, c.Position, c.HealthPercent));
            }
            return o;
        }

        public void Say(string words) { s.Say(words); }
        public void Attack(uint id) { s.Attack(id); }
        public void CancelAttack() { s.CancelAttack(); }
        public void Turn(Dir d) { s.Turn(d); }
        public int ItemCount(int clientId) => s.CountItem(clientId);
        public void UseOnSelf(int clientId) { s.UseItemOnCreature(clientId, P.W.PlayerId); }

        // ---- IHelperHostExt (track Q): allies, runes on a creature, food, summons
        public int Vocation => s.Spells.Vocation != 0 ? s.Spells.Vocation : P.W.PlayerVocation;
        public bool Hungry => false;   // the 10.98 state word (0xA2) has no hungry bit: food goes by the gap between meals
        public bool UseOnCreature(int clientId, uint creature) => s.UseItemOnCreature(clientId, creature);
        public bool UseItem(int clientId) => s.UseCarriedItem(clientId);

        public IList<HelperPlayer> Players()
        {
            var o = new List<HelperPlayer>();
            foreach (var c in P.W.Creatures.Values)
            {
                if (c.Type != 0 || c.HealthPercent <= 0) continue;
                o.Add(new HelperPlayer { Id = c.Id, Name = c.Name, Health = c.HealthPercent, Position = c.Position, Shield = c.Shield, IsSelf = c.Id == P.W.PlayerId });
            }
            return o;
        }

        public IList<string> OwnSummons()
        {
            var o = new List<string>();
            foreach (var c in P.W.Creatures.Values) if (c.Type == 3 && c.HealthPercent > 0) o.Add(c.Name);
            return o;
        }
    }
}
