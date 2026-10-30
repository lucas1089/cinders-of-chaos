//! Reload one config table (O312): the card "Recarregar um arquivo" of the Painel do jogo page. The server side is the
//! panel action `server.reload_file` (server/data/scripts/chaos/reload_file_core.lua, README "Reload one config
//! table (O312)"), reached with `chaos-ctl.sh reload-file ACTOR NAME`. This file checks the name before anything
//! leaves the PC (the same rule the shell script and the game apply again), says what kind of file it is, and builds
//! the command. A name is a bare file name of data/scripts/chaos: letters, digits and underscore, nothing else, so there
//! is nothing to inject.
use crate::ssh::sq;

/// What a reload of this file can do.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// A `*_config.lua` table: copied into the running game.
    Config,
    /// A script: not reloaded alone.
    Script,
    /// A config the game reads once at start.
    RestartOnly,
}

/// Configs that the game never takes live (mirrors `restartOnly` in reload_file_config.lua).
pub const RESTART_ONLY: [&str; 2] = ["remote_cmd_config", "reload_file_config"];

/// "pace_config", "pace_config.lua" or "data/scripts/chaos/pace_config.lua" gives "pace_config".
pub fn normalize(arg: &str) -> Result<String, String> {
    let a = arg.trim();
    if a.is_empty() {
        return Err("Escolha um arquivo.".into());
    }
    let a = a.strip_prefix("data/scripts/chaos/").unwrap_or(a);
    let a = a.strip_suffix(".lua").unwrap_or(a);
    let mut chars = a.chars();
    let ok_first = chars.next().is_some_and(|c| c.is_ascii_lowercase());
    if !ok_first
        || a.len() > 64
        || !a
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
    {
        return Err("Só o nome de um arquivo de data/scripts/chaos (letras minúsculas, números e _).".into());
    }
    Ok(a.to_string())
}

pub fn kind(name: &str) -> Kind {
    if RESTART_ONLY.contains(&name) {
        Kind::RestartOnly
    } else if name.ends_with("_config") {
        Kind::Config
    } else {
        Kind::Script
    }
}

/// What the owner reads next to the file name.
pub fn note(k: Kind) -> &'static str {
    match k {
        Kind::Config => {
            "Tabela de configuração: os valores novos entram no jogo agora, sem /reload. Um valor que o script copiou \
             ao carregar só muda com Recarregar scripts (Apply live) ou reinício."
        }
        Kind::Script => {
            "Script: não recarrega sozinho (registra eventos e guarda cópias). Precisa de Recarregar scripts (todos os \
             revscripts: Painel do jogo > Server > Reload system > scripts) ou de reinício."
        }
        Kind::RestartOnly => "Este arquivo é lido uma vez no início: precisa de reinício.",
    }
}

/// The chaos-ctl.sh arguments for the reload of `file`, empty `file` lists the tables the game can reload now.
pub fn args(actor: &str, file: &str) -> Result<String, String> {
    if actor.trim().is_empty() {
        return Err("Defina o personagem admin em Config.".into());
    }
    let name = if file.trim().is_empty() {
        String::new()
    } else {
        normalize(file)?
    };
    if name.is_empty() {
        Ok(format!("reload-file {}", sq(actor.trim())))
    } else {
        Ok(format!("reload-file {} {}", sq(actor.trim()), sq(&name)))
    }
}

/// The names `chaos-ctl.sh reload-files` printed: only valid config names, sorted, no repeats.
pub fn parse_list(out: &str) -> Vec<String> {
    let mut v: Vec<String> = out
        .lines()
        .map(str::trim)
        .filter(|l| normalize(l).is_ok_and(|n| n == *l && n.ends_with("_config")))
        .map(str::to_string)
        .collect();
    v.sort();
    v.dedup();
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_bare() {
        assert_eq!(normalize("pace_config").unwrap(), "pace_config");
        assert_eq!(normalize(" pace_config.lua ").unwrap(), "pace_config");
        assert_eq!(normalize("data/scripts/chaos/pace_config.lua").unwrap(), "pace_config");
        for bad in [
            "",
            "  ",
            "../pace_config",
            "data/scripts/chaos/../../config.lua",
            "data/lib/chaos_pay.lua",
            "a/b_config",
            "a b",
            "a;b",
            "a$(id)",
            "a`id`",
            "a'b",
            "a\"b",
            "A_config",
            "_config",
            "1_config",
            "a\nb",
            "a\\b",
            "/etc/passwd",
            "pace_config.luac",
        ] {
            assert!(normalize(bad).is_err(), "{bad:?}");
        }
        assert!(normalize(&"a".repeat(65)).is_err());
    }

    #[test]
    fn kinds() {
        assert_eq!(kind("pace_config"), Kind::Config);
        assert_eq!(kind("pace_core"), Kind::Script);
        assert_eq!(kind("pace"), Kind::Script);
        assert_eq!(kind("remote_cmd_config"), Kind::RestartOnly);
        assert!(note(Kind::Script).contains("reinício"));
        assert!(note(Kind::Config).contains("sem /reload"));
    }

    #[test]
    fn the_command_is_quoted() {
        assert_eq!(
            args("Admin One", "pace_config").unwrap(),
            "reload-file 'Admin One' 'pace_config'"
        );
        assert_eq!(args("Admin", "").unwrap(), "reload-file 'Admin'");
        // a quote in the actor stays inside the quotes
        assert_eq!(args("A'b", "x_config").unwrap(), "reload-file 'A'\\''b' 'x_config'");
        assert!(args("", "x_config").is_err());
        assert!(args("Admin", "x;rm -rf /").is_err());
    }

    #[test]
    fn list_keeps_only_config_names() {
        let out = "pace_config\narena_config\n../x_config\nnot a name\n\npace_config\nsome_core\nA_config\n";
        assert_eq!(parse_list(out), vec!["arena_config", "pace_config"]);
        assert!(parse_list("chaos-ctl: no dir\n").is_empty());
    }
}
