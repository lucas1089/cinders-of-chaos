// Phase 14, track H: the last windows of the smoke run that had no sample (Core/FakeModules.cs has the rules: the server's real JSON shape, the server file cited per message, the
// keys checked against that file by Core.Tests/FakeModulesTests.cs, the Unity state checked by Core.Tests/FakeModulesP14Tests.cs). Covered here:
//   Mentor (194): the status view of mentor_core.lua K.view (a registered mentor with two apprentices, the shop, the top list) and the browse answer.
//   Survey (122): the server opens it with `open {s, max}` at level 20 and 50 (survey.lua), so it is a context: the push before the step, `done` after.
//   Drop feed: the server sends no module message, it posts a text line to every client whose option allows it (retention_loot.lua post: a text message of type
//     MESSAGE_EVENT_ADVANCE with the item link). The smoke pushes that line (FakeGameServer.PushText) and the tests feed it to the chat model.
//   Battleground scoreboard: a match context (state with `match`, hud, board) instead of the end summary; the window asks `board` on opening, which the responder answers.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static partial class FakeModules
    {
        /// <summary>The module list of this file (added to FakeModules.Catalog).</summary>
        static IEnumerable<FakeModule> Phase14Modules()
        {
            yield return Mod("mentor", MentorPanel.Opcode, "mentor.lua, mentor_core.lua", "MentorWindow", "open", "sync", "list");
        }

        /// <summary>The answers of this file's modules; empty for an opcode or action not covered here. The Battleground "board" request is answered here too (its module is in FakeModulesP13.cs).</summary>
        static List<FakeMsg> Answer14(byte op, string action, object data)
        {
            var o = new List<FakeMsg>();
            if (op == MentorPanel.Opcode)
            {
                if (action == "open") o.Add(MentorStatus(true));
                else if (action == "sync") o.Add(MentorStatus(false));
                else if (action == "list") o.Add(MentorList());
            }
            else if (op == BattlegroundState.Opcode && action == "board") o.Add(BgBoard());
            return o;
        }

        // ------------------------------------------------------------------------------------ 194 mentor (mentor.lua sendStatus and sendList, mentor_core.lua K.view and K.milestoneRows)
        static FakeMsg MentorStatus(bool open) => M(MentorPanel.Opcode, "status",
            "{'enabled':true,'me':{'name':'Ember','level':310,'voc':'Juggernaut'}," +
            "'rules':{'exp':10,'dmg':15,'maxApprentices':3,'maxLevel':100,'gradLevel':100,'accountDays':30,'huntMinutes':10,'dailyHuntMarks':3,'monthlyCap':60,'minShared':20,'gradShared':60," +
            "'mentorLevel':200,'mentorHours':100,'mentorDays':30,'gradReward':'3 Orb of Binding, 1 Hunter Pouch','gradMarks':25}," +
            "'canMentor':true,'mentorNote':'','canPick':false,'pickNote':'You are too high a level to pick a mentor.','seeking':false,'graduated':false," +
            "'lines':[{'key':'warrior','name':'Warrior'},{'key':'ranger','name':'Ranger'},{'key':'mystic','name':'Mystic'},{'key':'necromancer','name':'Necromancer'}]," +
            "'invites':[{'guid':1105,'name':'Nova','level':18,'voc':'Pyromancer','lang':'Portuguese','left':540}]," +
            "'shop':[{'key':'title_guide','kind':'title','name':'Guide','desc':'A title for good teachers.','cost':30,'color':'#e8b84a','owned':false}," +
            "{'key':'supplies','kind':'item','name':'Mentor Supplies','desc':'Potions for your apprentices.','cost':10,'color':'#c8b89a','owned':false,'weeklyLeft':2}," +
            "{'key':'frame_mentor','kind':'cosmetic','name':'Mentor Frame','desc':'A frame for your portrait.','cost':60,'color':'#7fb8e8','owned':true}]," +
            "'top':[{'rank':1,'name':'Mira','graduates':14,'level':420,'voc':'Warden'},{'rank':2,'name':'Vex','graduates':9,'level':380,'voc':'Pyromancer'}]," +
            "'mentor':{'lang':'English','hours':'evenings','note':'Happy to explain the basics.','accepting':true,'public':true,'marks':35,'earned':120,'graduates':4,'dayMarks':1,'dayMinutes':25," +
            "'monthMarks':18,'linksThisMonth':1,'monthlyLinks':3,'apprentices':[" +
            "{'guid':1101,'name':'Kit','level':42,'voc':'Hunter','online':true,'linkedAt':1699000000,'shared':95,'source':'list','milestones':[" +
            "{'key':'l25','name':'Level 25','marks':5,'state':'paid','got':5},{'key':'l50','name':'Level 50','marks':8,'state':'open','got':0},{'key':'rift','name':'First rift','marks':5,'state':'open','got':0}," +
            "{'key':'graduation','name':'Level 100: graduation','marks':25,'state':'open','got':0}]}," +
            "{'guid':1102,'name':'Lyra','level':27,'voc':'Pyromancer','online':false,'linkedAt':1699500000,'shared':30,'source':'invite','milestones':[" +
            "{'key':'l25','name':'Level 25','marks':5,'state':'unearned','got':0},{'key':'graduation','name':'Level 100: graduation','marks':25,'state':'open','got':0}]}]}," +
            "'open':" + (open ? "true" : "false") + "}", Sc + "mentor.lua, mentor_core.lua (sendStatus, K.view)");

        static FakeMsg MentorList() => M(MentorPanel.Opcode, "mentors",
            "{'rows':[{'guid':1001,'name':'Mira','level':420,'voc':'Warden','line':'warrior','lang':'English','hours':'weekends','note':'Patient, loves dungeons.','graduates':14,'active':1,'max':3,'online':true}," +
            "{'guid':1002,'name':'Vex','level':380,'voc':'Pyromancer','line':'mystic','lang':'Portuguese','hours':'','note':'','graduates':9,'active':3,'max':3,'online':false}]," +
            "'filter':{'line':'','lang':'','online':'any'}}", Sc + "mentor.lua (sendList)");

        // ------------------------------------------------------------------------------------ 122 survey (survey.lua: open {s, max}, done {s})
        /// <summary>What the server pushes at level 20 (the stage with the "where did you hear" question).</summary>
        public static FakeMsg SurveyOpen(int stage) => M(SurveyPanel.Opcode, "open", "{'s':" + stage + ",'max':200}", Sc + "survey.lua, survey_config.lua (the open push)");
        public static FakeMsg SurveyDone(int stage) => M(SurveyPanel.Opcode, "done", "{'s':" + stage + "}", Sc + "survey.lua (done)");

        // ------------------------------------------------------------------------------------ the drop feed (retention_loot.lua post, retention_loot_config.lua feed.text, retention_loot_core.lua feedLine)
        /// <summary>The server's text type of the line (MESSAGE_EVENT_ADVANCE, `feed.fallbackType`).</summary>
        public const byte DropFeedTextType = 19;
        /// <summary>The id of a link the way itemlink.lua makes it: [Name]{r id}, r a rarity hex digit or u for a unique, id nine characters of a-z and 0-9.</summary>
        public const string DropFeedItemName = "Emberfang", DropFeedLinkId = "k3x9q2m7a";

        /// <summary>The line the drop feed posts: `feed.text` ("%s (Lv %d) found %s!") filled by RetentionLootCore feedLine with the player, the level and the link token.</summary>
        public static string DropFeedLine(string player = "Vex", int level = 310, bool unique = true) =>
            player + " (Lv " + level + ") found [" + DropFeedItemName + "]{" + (unique ? "u" : "5") + DropFeedLinkId + "}!";

        // ------------------------------------------------------------------------------------ 200 battleground: the live scoreboard of a match (battleground.lua board and hudOf)
        static FakeMsg BgBoard() => M(BattlegroundState.Opcode, "board",
            "{'rows':[{'name':'Ember','team':1,'role':'dps','level':300,'kills':12,'assists':4,'downs':2,'captures':3,'damage':250000,'healing':1000,'voc':'Juggernaut'}," +
            "{'name':'Nova','team':1,'role':'healer','level':290,'kills':2,'assists':14,'downs':3,'captures':1,'damage':20000,'healing':310000,'voc':'Templar'}," +
            "{'name':'Vex','team':2,'role':'tank','level':310,'kills':8,'assists':2,'downs':5,'captures':1,'damage':180000,'healing':0,'voc':'Warden'}," +
            "{'name':'Zed','team':2,'role':'dps','level':305,'kills':6,'assists':3,'downs':6,'captures':0,'damage':160000,'healing':0,'voc':'Pyromancer','left':true}]," +
            "'teams':['Ash','Frost'],'score':[120,95]}", Sc + "battleground.lua (board and scoreboardOf)");

        /// <summary>The summary the server sends when the match ends (the end view of the same window; kept for the tests, the smoke shows the live board).</summary>
        public static FakeMsg BgEnd() => M(BattlegroundState.Opcode, "end",
            "{'result':'win','reason':'score','rated':true,'team':1,'teams':['Ash','Frost'],'score':[300,210],'winner':1,'honor':40,'firstWin':true,'items':'','duration':900," +
            "'rows':[{'name':'Ember','team':1,'role':'dps','level':300,'kills':12,'assists':4,'downs':2,'captures':3,'damage':250000,'healing':1000,'honor':40,'voc':'Juggernaut'},{'name':'Vex','team':2,'role':'tank','level':310,'kills':8,'assists':2,'downs':5,'captures':1,'damage':180000,'healing':0,'honor':10,'voc':'Warden'}]}",
            Sc + "battleground.lua (end and scoreboardOf)");

        // ------------------------------------------------------------------------------------ the contexts of this file
        static void AddContexts14(Dictionary<string, FakeContext> d)
        {
            // the server opens the survey itself at level 20 and 50: the push opens the window, `done` closes it after the step
            Ctx(d, "SurveyWindow", Sc + "survey.lua", SurveyOpen(SurveyPanel.SourceStage));
            d["SurveyWindow"].Close.Add(SurveyDone(SurveyPanel.SourceStage));
            // a running match: the state with `match` (so the window knows it is in one), the hud and the board; the window asks `board` when it opens and the responder answers
            Ctx(d, "BattlegroundBoardWindow", Sc + "battleground.lua",
                M(BattlegroundState.Opcode, "state", "{'open':false,'enabled':true,'match':{'phase':'fight','team':1}}", Sc + "battleground.lua (B.stateOf: the match member)"),
                M(BattlegroundState.Opcode, "hud", "{'phase':'fight','left':600,'score':[120,95],'win':300,'braziers':[],'team':1,'teams':['Ash','Frost'],'colors':['#c0501a','#3a6fc0'],'players':[8,8]}", Sc + "battleground.lua (hudOf)"),
                BgBoard());
        }
    }
}
