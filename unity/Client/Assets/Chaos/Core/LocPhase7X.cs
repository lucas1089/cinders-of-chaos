// pt-BR texts of the phase 7 track X systems (character cards with wings, aura and shader, the create character window, the spellbook area preview and
// detail rows, the hotbar options and side slots, the helper's Follow, Auto sell, exercise weapon, level-up notice and potion gate, the top menu's More
// sub-menus and System entries), merged into LocStrings.PtBr by its static constructor. Entries that LocStrings already has win.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class LocPhase7X
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            // create character
            { "Male", "Masculino" }, { "Female", "Feminino" }, 
            { "I understand", "Eu entendo" }, { "Open the Terms page", "Abrir a página dos Termos" }, { "Create", "Criar" }, 
            { "Enter a name.", "Digite um nome." }, { "Use letters and spaces only.", "Use só letras e espaços." },
            { "Use one space between words.", "Use um espaço entre as palavras." }, { "Every word needs at least two letters.", "Cada palavra precisa de pelo menos duas letras." },
            { "Use at most {0} words.", "Use no máximo {0} palavras." }, { "The name needs {0} to {1} letters.", "O nome precisa de {0} a {1} letras." },
            { "{0} to {1} letters, up to {2} words.", "{0} a {1} letras, até {2} palavras." },
            { "No season (standard character)", "Sem temporada (personagem padrão)" }, { "Choose a class.", "Escolha uma classe." },
            { "{0}: locked for this account. Reach level 200 with any character of your account to unlock it.", "{0}: bloqueada nesta conta. Chegue ao nível 200 com qualquer personagem da conta para liberar." },
            { "a base class. You choose its ascension at level 100.", "uma classe base. Você escolhe a ascensão no nível 100." },
            { "Creating your character...", "Criando seu personagem..." }, { "Reading your account from the website...", "Lendo sua conta no site..." },
            { "Accept the current Terms of Use on the website first, then come back.", "Aceite primeiro os Termos de Uso atuais no site e volte." },
            { "Hardcore has one life: tick \"I understand\" to choose it.", "Hardcore tem uma vida só: marque \"Eu entendo\" para escolher." },
            { "No free character slot: more are sold in the game store (Storage & Slots > Character Slot).", "Sem vaga livre de personagem: há mais à venda na loja do jogo (Armazenamento e Vagas > Vaga de Personagem)." },
            { "Character slots: {0} of {1} used.", "Vagas de personagem: {0} de {1} em uso." }, { "Created.", "Criado." },
            { "The website gave no answer.", "O site não respondeu." },
            // spellbook
            { "Hit", "Acerta" }, { "You", "Você" }, { "Soul", "Alma" }, { "Type", "Tipo" }, { "Element", "Elemento" },
            { "Scales", "Escala" }, { "Vocations", "Vocações" }, { "Special", "Especial" },
            { "Conjure", "Conjuração" }, { "Utility", "Utilidade" }, { "Single target", "Alvo único" },
            { "Area", "Área" }, { "Self", "Própria" }, { "Area in front", "Área à frente" }, { "Everyone", "Todos" }, { "Every class", "Todas as classes" },
            { "{0} classes", "{0} classes" }, { "Affects only you.", "Afeta só você." }, { "Cast facing north (up).", "Lance virado para o norte (cima)." },
            { "Centred on the target.", "Centrada no alvo." }, { "Centred on you.", "Centrada em você." }, { "One target, range {0}.", "Um alvo, alcance {0}." },
            { "One target.", "Um alvo." },
            // hotbar
            { "Bar size: {0}%", "Tamanho da barra: {0}%" }, 
            { "Drop an item on a slot to keep it there. Drag a slot to move it.", "Solte um item num espaço para guardá-lo. Arraste um espaço para movê-lo." },
            // helper: follow, sell, exercise, level-up
            { "Follow and sell", "Seguir e vender" }, { "Auto-update my spells", "Atualizar minhas magias sozinho" },
            { "New spell available: {0}.", "Nova magia disponível: {0}." }, { "Add to rotation?", "Adicionar à rotação?" }, { "Ignore", "Ignorar" },
            { "Added {0} spell(s) to the rotation.", "{0} magia(s) adicionada(s) à rotação." }, { "The five slots are in use: clear one first.", "Os cinco espaços estão em uso: libere um antes." },
            { "Follow a player", "Seguir um jogador" }, { "A friend by name", "Um amigo pelo nome" }, { "The party leader", "O líder do grupo" },
            { "Distance", "Distância" }, { " tiles", " tiles" },
            { "Asks the server to walk you after the player. The fight systems pause while you follow. Not in a protection zone.", "Pede ao servidor para andar atrás do jogador. Os sistemas de luta pausam enquanto você segue. Não vale em zona de proteção." },
            { "Auto sell", "Venda automática" }, { "Sell my Loot Bag", "Vender minha Bolsa de Loot" }, { "Every", "A cada" }, { "Also when capacity is low", "Também com pouca capacidade" },
            { "Only asks the Auto Seller; the server decides what is sold. Needs the Auto Seller (Store, Convenience) or an active Chaos Pact.", "Só pede ao Vendedor Automático; o servidor decide o que é vendido. Precisa do Vendedor Automático (Loja, Conveniência) ou de um Pacto do Caos ativo." },
            { "Exercise weapon", "Arma de treino" }, { "Train on a dummy", "Treinar num boneco" }, { "Any exercise weapon I carry", "Qualquer arma de treino que eu carregue" },
            { "Exercise Sword", "Espada de Treino" }, { "Exercise Fist Weapon", "Arma de Punho de Treino" }, { "Exercise Club", "Clava de Treino" }, { "Exercise Bow", "Arco de Treino" },
            { "Exercise Rod", "Cajado de Treino" }, { "Exercise Wand", "Varinha de Treino" }, { "Durable Exercise Sword", "Espada de Treino Durável" }, { "Exercise Shield", "Escudo de Treino" },
            { "In a protection zone, standing still for two seconds, uses the weapon on a training dummy within five tiles.", "Numa zona de proteção, parado por dois segundos, usa a arma num boneco de treino a até cinco tiles." },
            { "Following", "Seguindo" }, { "Asking to follow", "Pedindo para seguir" }, { "Leader out of view", "Líder fora de vista" }, { "Close enough", "Perto o bastante" },
            { "Next to the leader", "Ao lado do líder" }, { "Following someone else", "Seguindo outra pessoa" }, { "Cannot reach the leader", "Não alcança o líder" }, 
            { "Asked the Auto Seller", "Pediu ao Vendedor Automático" }, { "Waiting for the timer", "Esperando o relógio" }, { "The Auto Seller is cooling down", "O Vendedor Automático está em recarga" },
            { "The Auto Seller is not unlocked", "O Vendedor Automático não está liberado" }, { "Asking the server about the Auto Seller", "Perguntando ao servidor sobre o Vendedor Automático" },
            // top menu
            { "Class changed: {0} spell(s) of your old class were taken out of the Helper. Press Auto setup for your new class.", "Classe mudou: {0} magia(s) da sua classe antiga saíram do Ajudante. Aperte Configuração automática para a nova classe." },
            { "Inventory", "Inventário" }, { "Join Discord", "Entrar no Discord" }, { "Logout", "Sair da conta" }, { "Exit", "Sair do jogo" }, { "The community link is not available yet.", "O link da comunidade ainda não está disponível." },
        };
    }
}
