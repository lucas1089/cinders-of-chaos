// Base gameplay actions of GameParser and GameSession (track P): player trade, the VIP list, the quest log, look, use with, rotate, and the dead guard.
// Models: Play.cs, PlayLists.cs, PlayGuards.cs.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed partial class GameParser
    {
        public readonly PlayerTradeState PlayerTrade = new PlayerTradeState();
        public readonly VipState Vip = new VipState();
        public readonly QuestLogState Quests = new QuestLogState();

        /// <summary>0x7D, 0x7E, 0x7F (trade), 0xD2, 0xD3, 0xD4 (VIP), 0xF0, 0xF1 (quest log).</summary>
        void PlayMessage(byte op, ByteReader r)
        {
            switch (op)
            {
                case 0x7D: case 0x7E: PlayerTrade.Read(op, r, rd => ReadItem(rd, rd.U16())); break;
                case 0x7F: PlayerTrade.Closed(); break;
                case 0xD2: Vip.ReadEntry(r); break;
                case 0xD3: Vip.ReadStatus(r); break;
                case 0xD4: Vip.ReadLogout(r); break;   // the old logout message (u32 guid); TFS 1.4.2 sends 0xD3 with a status instead
                case 0xF0: Quests.ReadLog(r); break;
                case 0xF1: Quests.ReadLine(r); break;
            }
        }
    }

    public sealed partial class GameSession
    {
        public PlayerTradeState PlayerTrade => parser.PlayerTrade;
        public VipState Vip => parser.Vip;
        public QuestLogState Quests => parser.Quests;
        public readonly DeadGuard Dead = new DeadGuard();
        public readonly TargetLock TargetLocks = new TargetLock();
        double nextSweep;

        void InitPlay()
        {
            Action<byte[]> send = p => conn?.Send(p);
            parser.PlayerTrade.Send = send;
            parser.Vip.Send = send;
            parser.Quests.Send = send;
        }

        /// <summary>Called by Poll: the dead guard sweeps once a second.</summary>
        void PlayPoll()
        {
            if (!parser.LoggedIn || Now < nextSweep) return;
            nextSweep = Now + DeadGuard.SweepMs;
            var list = new List<DeadGuard.Seen>();
            uint me = world.PlayerId;
            foreach (var c in world.Creatures.Values)
                list.Add(new DeadGuard.Seen { Id = c.Id, IsPlayer = c.Type == 0, IsSelf = c.Id == me, Health = c.HealthPercent, OnMap = c.Position.X > 0 });
            foreach (uint id in Dead.Sweep(list, Now))
            {
                if (!world.Creatures.TryGetValue(id, out var c)) continue;
                if (parser.AttackTarget == id) CancelAttack();
                world.RemoveCreature(c);
                world.Creatures.Remove(id);
                Log("deadguard: removed " + id + " " + c.Name);
            }
        }

        /// <summary>The Auto Target class of a creature (1 loot goblin, 2 boss, 3 special, 4 normal): its name and the tier the monster bar heard. Asks the server about a
        /// creature it has not named (at most once in 30 s per creature).</summary>
        public int AutoTargetRank(uint id)
        {
            if (!world.Creatures.TryGetValue(id, out var c)) return AutoTargetCore.RankNormal;
            var info = Hud.Monster.Info(id);
            if (info == null) Hud.Monster.Query(id, Now);
            return AutoTargetCore.ClassOf(c.Name, info?.Tier, info?.Role);
        }

        // ---- look, use with, rotate (the answer to a look is the text message already shown)
        public void Look(ItemRef r) { if (r.Item != null) conn?.Send(PlayPackets.Look(r.Pos, r.Id, r.Stack)); }
        public void LookAtCreature(uint id) { conn?.Send(PlayPackets.LookCreature(id)); }
        public void Rotate(ItemRef r) { if (r.Item != null) conn?.Send(PlayPackets.Rotate(r.Pos, r.Id, r.Stack)); }
        public void SendRaw(byte[] packet) { if (packet != null) conn?.Send(packet); }
    }
}
