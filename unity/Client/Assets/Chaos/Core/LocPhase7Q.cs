// pt-BR texts of phase 7, track Q (UI, map and visual systems), merged into LocStrings.PtBr by its static constructor. Entries that LocStrings already has win.
// Phase7QTests checks that every text the track's files ask for has an entry here or there and that the {n} placeholders match.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class LocPhase7Q
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            { "Ctrl and the mouse wheel over the map zoom too. Wide view asks the server for the largest area, so up to 19 rows show in the classic view (11 in HD-2D and the live view).", "Ctrl e a roda do mouse sobre o mapa também dão zoom. A visão ampla pede ao servidor a maior área, então até 19 linhas aparecem na visão clássica (11 no HD-2D e na visão ao vivo)." },
            { "Wide view (ask the server for 29 x 21 tiles)", "Visão ampla (pedir ao servidor 29 x 21 quadrados)" },
            { "Interface scale", "Escala da interface" },
            { "Dark fantasy window frames", "Molduras de janela de fantasia sombria" },
            { "Window skin: {0}", "Aparência das janelas: {0}" },
            { "Classic", "Clássica" }, { "Forge and Embers", "Forja e Brasas" }, { "Abyssal Arcane", "Arcano Abissal" },
            { "Rain, embers and area colours", "Chuva, brasas e cores da área" },
            { "STREAMER", "STREAMER" },
            { "Streamer mode is on (Ctrl+Shift+S). Options > Misc.", "Modo streamer ligado (Ctrl+Shift+S). Opções > Diversos." },
        };
    }
}
