// pt-BR texts of the sound, visual effect and layout options (phase 5, track R), merged into LocStrings.PtBr by its static constructor. Entries that LocStrings already has win;
// VisualTests checks that every text the new files ask for exists here or there and that the {n} placeholders match.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class LocVisual
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            { "General", "Geral" }, { "Sound", "Som" }, { "Visuals", "Visual" }, { "Layout", "Layout" },
            { "Town", "Cidade" }, { "Hunt", "Caçada" }, { "Dungeon", "Masmorra" }, { "Boss", "Boss" }, { "Arena", "Arena" }, { "Login", "Entrada" },
            { "Drag the frames to move the HUD pieces. Double click puts one back.", "Arraste as molduras para mover as peças da tela. Clique duplo devolve uma ao lugar." },
            { "Done", "Pronto" }, { "Name shaders", "Sombreados de nome" }, { "Name shader equipped: {0}", "Sombreado de nome equipado: {0}" },
            { "Name shader unlocked: {0}", "Sombreado de nome desbloqueado: {0}" }, { "Search", "Buscar" },
            { "The list comes with the outfit window.", "A lista vem com a janela de visual." }, { "Load the list", "Carregar a lista" },
            { "Equipped", "Equipado" }, { "Locked", "Bloqueado" }, { "Equip", "Equipar" },
            { "Game sounds", "Sons do jogo" }, { "Volume", "Volume" }, { "Quiet", "Baixo" }, { "Normal", "Normal" }, { "Loud", "Alto" },
            { "Combat sounds", "Sons de combate" }, { "Spell sounds", "Sons de magias" }, { "Level up, loot and goals", "Nível, loot e metas" },
            { "Window sounds", "Sons de janelas" }, { "Play a test sound", "Tocar um som de teste" }, { "Region music", "Música da região" },
            { "Music volume", "Volume da música" }, { "Mute the music when the window is in the background", "Silenciar a música com a janela em segundo plano" },
            { "Now playing: {0}", "Tocando: {0}" },
            { "The sound files were not found. Set CHAOS_OVERLAY_DIR to the folder client/overlay/modules.", "Os arquivos de som não foram achados. Defina CHAOS_OVERLAY_DIR com a pasta client/overlay/modules." },
            { "Spell effect opacity", "Opacidade dos efeitos de magia" }, { "Hit flash", "Brilho ao ser atingido" }, { "Screen shake on big hits", "Tremor da tela em golpes fortes" },
            { "Stains on the ground after combat", "Manchas no chão após o combate" }, { "Loot beams", "Feixes de loot" },
            { "Beams on ground items too", "Feixes também em itens no chão" }, { "Beams for orbs", "Feixes para orbes" }, { "Beam height", "Altura do feixe" },
            { "Short", "Baixo" }, { "Tall", "Alto" }, { "Beam light", "Luz do feixe" }, { "Soft", "Suave" }, { "Bright", "Forte" },
            { "Chest and Templar auras", "Auras de baús e de Templários" }, { "Level-up wings on my character", "Asas de nível no meu personagem" },
            { "Level-up wings on other characters", "Asas de nível em outros personagens" }, { "Footprints of other characters", "Pegadas de outros personagens" },
            { "Glows of other characters", "Brilhos de outros personagens" }, { "Error messages in their own colour", "Mensagens de erro em cor própria" },
            { "Fade windows in and out", "Janelas aparecem e somem suavemente" }, { "Name shaders...", "Sombreados de nome..." },
            { "Map zoom", "Zoom do mapa" }, { "{0} rows", "{0} linhas" },
            { "Ctrl and the mouse wheel over the map zoom too. A larger area than 11 rows needs the server's view range, not sent yet.", "Ctrl e a roda do mouse sobre o mapa também dão zoom. Uma área maior que 11 linhas precisa do alcance de visão do servidor, ainda não enviado." },
            { "Move the HUD pieces", "Mover as peças da tela" }, { "Put the HUD pieces back", "Devolver as peças da tela ao lugar" },
            { "Remember window places per character", "Lembrar o lugar das janelas por personagem" },
        };
    }
}
