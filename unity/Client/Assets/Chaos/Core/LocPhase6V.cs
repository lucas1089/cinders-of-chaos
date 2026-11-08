// pt-BR texts of phase 6, track V (login news, character select extras, bag panel, plate, NPC bubble, party frames settings, auto-walk, split stack),
// merged into LocStrings.PtBr by its static constructor. Entries that LocStrings or an earlier file already has win. Phase6VTests checks that every text
// the track's sources ask for has an entry and that the {n} placeholders match.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class LocPhase6V
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            // login screen
            { "Server online - {0} players", "Servidor online - {0} jogadores" }, { "Event schedule", "Calendário de eventos" },
            { "Boosted today", "Reforçados hoje" }, { "Creature", "Criatura" }, { "now", "agora" }, { "tomorrow", "amanhã" }, { "in {0} days", "em {0} dias" },
            // character select
            { "{0} characters, no free slot", "{0} personagens, sem vaga livre" }, { "{0} characters, {1} of {2} slots used", "{0} personagens, {1} de {2} vagas usadas" },
            { "Load wings, aura, last login and slots from the website", "Carregar asas, aura, último acesso e vagas do site" },
            { "Wings", "Asas" }, { "Aura", "Aura" },
            { "never played", "nunca jogou" }, { "just now", "agora mesmo" }, { "{0} minutes ago", "há {0} minutos" }, { "an hour ago", "há uma hora" },
            { "{0} hours ago", "há {0} horas" }, { "yesterday", "ontem" }, { "{0} days ago", "há {0} dias" }, { "{0}", "{0}" },
            // bag panel (equipment window)
            { "Equip", "Equipar" }, { "Quest", "Missões" }, { "Stats", "Atributos" }, { "Shop", "Loja" },
            { "Cap: {0}", "Cap: {0}" }, { "Soul: {0}", "Alma: {0}" }, { "Gold: {0}", "Ouro: {0}" }, { "Chaos Coins: {0}", "Chaos Coins: {0}" },
            { "{0} gold, {1} platinum, {2} crystal", "{0} ouro, {1} platina, {2} cristal" },
            // plate
            { "Show numbers", "Mostrar números" }, { "Show percent", "Mostrar porcentagem" }, { "Eased bars: on", "Barras suaves: ligadas" }, { "Eased bars: off", "Barras suaves: desligadas" },
            // NPC and walking
            { "Talk", "Conversar" }, { "Look", "Olhar" }, { "Copy Name", "Copiar nome" }, { "You cannot reach {0}.", "Você não consegue chegar em {0}." }, { "There is no way.", "Não há caminho." },
            // split stack
            { "Move how many?", "Mover quantos?" }, { "Half", "Metade" }, { "All", "Tudo" }, { "Move", "Mover" }, { "Cancel", "Cancelar" },
            // party frames settings
            { "Scale: {0}%", "Escala: {0}%" }, { "Show the panel when in a party", "Mostrar o painel em grupo" }, { "Show myself", "Mostrar a mim mesmo" }, { "Show buffs", "Mostrar buffs" },
            { "Clicking a member follows", "Clicar em um membro segue" }, { "Lock the panel", "Travar o painel" }, { "{0}s", "{0}s" },
        };
    }
}
