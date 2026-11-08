// pt-BR texts of the phase 7 track Y systems (the passive tree's Paragon panel and other characters' trees, ground label tooltips, the rarity outline
// option), merged into LocStrings.PtBr by its static constructor. Entries that LocStrings already has win.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class LocPhase7Y
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            { "... and {0} more", "... e mais {0}" },
            { "Click: open the corpse", "Clique: abrir o corpo" },
            { "Back to my tree", "Voltar à minha árvore" },
            { "View tree", "Ver árvore" },
            { "Paragon", "Paragon" },
            { "+{0}% per point, up to +{1}% ({2} points).", "+{0}% por ponto, até +{1}% ({2} pontos)." },
            { "Available: {0}     Spent: {1}     Total: {2}", "Disponíveis: {0}     Gastos: {1}     Total: {2}" },
            { "Every level above {0} gives one Paragon point for small, capped bonuses: damage, health, speed, gold and item find.", "Cada nível acima de {0} dá um ponto Paragon para bônus pequenos e limitados: dano, vida, velocidade, ouro e achado de itens." },
            { "Refund every Paragon point for {0} gold (level x 250).", "Devolve todos os pontos Paragon por {0} de ouro (nível x 250)." },
            { "Refund all {0} Paragon points for {1}? Proceed?", "Devolver todos os {0} pontos Paragon por {1}? Continuar?" },
            { "+{0}% {1} (Paragon).", "+{0}% {1} (Paragon)." },
            { "{0}: {1} passive node (read-only)", "{0}: {1} nó passivo (somente leitura)" },
            { "{0}: {1} passive nodes (read-only)", "{0}: {1} nós passivos (somente leitura)" },
            { "Rarity outline on items on the map", "Contorno de raridade nos itens do mapa" },
            { "Filter rule: {0}", "Regra do filtro: {0}" },
            { "session", "sessão" },
            { "Since login: {0}   Total: {1}", "Desde o login: {0}   Total: {1}" },
        };
    }
}
