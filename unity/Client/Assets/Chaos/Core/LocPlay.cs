// pt-BR texts of the base gameplay actions (track P): item menu, trade, VIP list, quest log, look preview. Merged into LocStrings.PtBr by its static constructor;
// entries that LocStrings already has win. A test (PlayTests) checks that every text asked for exists here or there and that the {n} placeholders match.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class LocPlay
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            { "A name has letters only.", "Um nome tem só letras." }, { "Accept", "Aceitar" }, { "Add", "Adicionar" },
            { "Add the names of your friends to see when they are online.", "Adicione os nomes dos seus amigos para ver quando estão online." },
            { "Add to Loot List", "Adicionar à lista de loot" }, { "Badge", "Insígnia" }, { "Cancel", "Cancelar" },
            { "Click an item to look at it. Accept when both offers are right.", "Clique num item para olhá-lo. Aceite quando as duas ofertas estiverem certas." },
            { "Click another player to trade with.", "Clique em outro jogador para negociar." }, { "Copy Name", "Copiar nome" },
            { "Edit", "Editar" }, { "Edit {0}", "Editar {0}" }, { "Effects play in the game world.", "Os efeitos aparecem no mundo do jogo." },
            { "Footprints are left on the ground as you walk.", "Pegadas ficam no chão enquanto você anda." }, { "Hide completed quests", "Esconder quests concluídas" },
            { "Icon {0}", "Ícone {0}" }, { "Item looks show on the item, not on the character.", "Os visuais de item aparecem no item, não no personagem." },
            { "Loading...", "Carregando..." }, { "Lock item", "Travar item" }, { "Look", "Olhar" }, { "Look Preview", "Prévia do visual" },
            { "Look {0}, addons {1}", "Visual {0}, addons {1}" }, { "Name plates show over characters in the game world.", "As placas de nome aparecem sobre os personagens no mundo do jogo." },
            { "No trade is open.", "Nenhuma negociação aberta." }, { "Nobody matches.", "Ninguém corresponde." }, { "Open", "Abrir" },
            { "Outlines show in the game world.", "Os contornos aparecem no mundo do jogo." }, { "Pick a quest to read its missions.", "Escolha uma quest para ler suas missões." },
            { "Plain figure", "Figura simples" }, { "Pouch settings", "Configurações da bolsa" }, { "Quest Log", "Diário de quests" }, { "Refresh", "Atualizar" },
            { "Reject", "Recusar" }, { "Remove", "Remover" }, { "Remove from Loot List", "Remover da lista de loot" }, { "Rotate", "Girar" }, { "Save", "Salvar" },
            { "Send message", "Enviar mensagem" }, { "Slow turn", "Giro lento" }, { "Tell me when they log in", "Avise quando entrarem" },
            { "The name is too long.", "O nome é longo demais." }, { "This shader is not in your client yet.", "Este shader ainda não está no seu cliente." },
            { "Trade", "Negociar" }, { "Trade with ...", "Negociar com ..." }, { "Trade with ...: click a player. Right click or Esc cancels.", "Negociar com ...: clique num jogador. Botão direito ou Esc cancela." },
            { "Transmog", "Transmogrificar" }, { "Type the name of a player.", "Digite o nome de um jogador." }, { "Unlock item", "Destravar item" }, { "Use", "Usar" },
            { "Use with ...", "Usar com ..." }, { "Use with ...: click a target. Right click or Esc cancels.", "Usar com ...: clique num alvo. Botão direito ou Esc cancela." },
            { "VIP List", "Lista VIP" }, { "Waiting for the other offer.", "Esperando a outra oferta." }, { "Where to find", "Onde achar" },
            { "You accepted. Waiting for {0}.", "Você aceitou. Esperando {0}." }, { "Your offer", "Sua oferta" }, { "aura {0}", "aura {0}" },
            { "mount {0}", "montaria {0}" }, { "shader {0}", "shader {0}" }, { "wings {0}", "asas {0}" }, { "{0} is on the list already.", "{0} já está na lista." },
            { "{0} of {1} quests done", "{0} de {1} quests concluídas" }, { "{0} online of {1}", "{0} online de {1}" }, { "{0}'s offer", "Oferta de {0}" },
        };
    }
}
