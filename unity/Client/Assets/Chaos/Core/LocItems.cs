// pt-BR texts of the items and economy windows (tooltips, outfit window, bank, stash, store, modal and text windows). Kept in a file of its own and
// merged into LocStrings.PtBr by its static constructor (indexer, so a key another file also has is not an error). Keys are the English text.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class LocItems
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            // tooltip (Core/ItemInfo.cs) and the rarity names of the server's tooltip
            { "Common", "Comum" }, { "Uncommon", "Incomum" }, { "Magic", "Mágica" }, { "Rare", "Rara" }, { "Legendary", "Lendária" }, { "Divine", "Divina" },
            { "Set", "Conjunto" }, { "Unique", "Único" },
            { "Item Level {0}", "Nível do item {0}" }, { "  (up to T{0})", "  (até T{0})" },
            { "Quality +{0}%  (up to {1}%)", "Qualidade +{0}%  (até {1}%)" },
            { "Ruined: no orb can change this item", "Arruinado: nenhum orbe muda este item" },
            { "Corrupted: no orb can change this item", "Corrompido: nenhum orbe muda este item" },
            { "Prefixes", "Prefixos" }, { "Suffixes", "Sufixos" }, { "Corrupted implicit", "Implícito corrompido" }, { "[bound]", "[ligado]" },
            { "Veiled", "Velado" }, { "Veiled modifier", "Modificador velado" }, { "  Reveal it with an Orb of Unveiling", "  Revele com um Orbe do Desvelar" },
            { "Sockets {0}/{1}", "Engastes {0}/{1}" }, { "  empty socket", "  engaste vazio" },
            { "Set: {0} ({1}/{2})", "Conjunto: {0} ({1}/{2})" }, { "Active tier: {0} of {1}", "Nível ativo: {0} de {1}" },
            { " (counts {0})", " (conta {0})" }, { " (level {0})", " (nível {0})" },
            { "Requires level {0}", "Requer nível {0}" }, { "Requires magic level {0}", "Requer nível mágico {0}" }, { "For {0}", "Para {0}" },
            { "Locked", "Trancado" }, { "Appearance: {0}", "Aparência: {0}" },
            { "Charges: unlimited", "Cargas: ilimitadas" }, { "Charges: {0} of {1}", "Cargas: {0} de {1}" }, { "Charges: {0}", "Cargas: {0}" },
            { "Weight {0} oz", "Peso {0} oz" },
            // outfit window
            { "Outfit", "Visual" }, { "Mount", "Montaria" }, { "Wings", "Asas" }, { "Aura", "Aura" }, { "Shader", "Sombreador" }, { "Colors", "Cores" },
            { "Head", "Cabeça" }, { "Primary", "Primária" }, { "Secondary", "Secundária" }, { "Detail", "Detalhe" }, { "Addon {0}", "Adicional {0}" },
            { "Asking the server...", "Perguntando ao servidor..." }, { "None", "Nenhum" }, { "Ok", "Ok" }, { "Cancel", "Cancelar" }, { "Close", "Fechar" },
            // bank
            { "Bank", "Banco" }, { "Gold you carry", "Ouro que você leva" }, { "Gold in the bank", "Ouro no banco" }, { "Deposit", "Depositar" },
            { "Withdraw", "Sacar" }, { "Transfer", "Transferir" }, { "Deposit all", "Depositar tudo" }, { "Withdraw all", "Sacar tudo" },
            { "Pick Deposit, Withdraw or Transfer to type an amount.", "Escolha Depositar, Sacar ou Transferir para digitar um valor." },
            { "To", "Para" }, { "All", "Tudo" },
            // stash
            { "Stash", "Baú" }, { "Sorted by amount", "Por quantidade" }, { "Sorted by name", "Por nome" }, { "Nothing here.", "Nada aqui." },
            { "Loading the stash...", "Carregando o baú..." }, { "Take out", "Retirar" }, { "Stow everything", "Guardar tudo" }, { "Inbox ({0})", "Caixa ({0})" },
            { "Slots", "Espaços" }, { "Drag an item here to store it.", "Arraste um item para cá para guardá-lo." },
            { "Stowed {0}, kept {1}.", "Guardados {0}, mantidos {1}." },
            { "You can take items out only in a protection zone or a hideout.", "Você só retira itens numa zona de proteção ou num esconderijo." },
            { "You can deposit items only in town.", "Você só guarda itens na cidade." }, { "Remote deposit is locked.", "O depósito remoto está bloqueado." },
            // store
            { "Store", "Loja" }, { "Search the store", "Buscar na loja" }, { "History", "Histórico" }, { "Chaos Coins: {0}", "Moedas do Caos: {0}" },
            { "Chaos Coins are added on the website.", "As Moedas do Caos são adicionadas no site." }, { "Transaction history", "Histórico de compras" },
            { "Search \"{0}\": {1} offers", "Busca \"{0}\": {1} ofertas" }, { "Loading the store...", "Carregando a loja..." },
            { "Previous", "Anterior" }, { "Next", "Próxima" }, { "Page {0} of {1}", "Página {0} de {1}" }, { "{0} ({1} coins)", "{0} ({1} moedas)" },
            { "was {0}", "era {0}" }, { "Owned", "Já tem" }, { "Yes", "Sim" }, { "No", "Não" },
            { "Do you want to buy {0} for {1} Chaos Coins?", "Quer comprar {0} por {1} Moedas do Caos?" },
            // text window
            { "Door list", "Lista da porta" }, { "Writing", "Escrita" }, { "Text", "Texto" }, { "Written by {0}", "Escrito por {0}" },
            { "Up to {0} characters.", "Até {0} caracteres." },
        };
    }
}
