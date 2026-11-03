//! Navigation of the window (O383): the sidebar categories and the search box. Pure functions over the command table,
//! so the tests see what the owner sees. Owner 2026-11-03: "too many collapsible sections, hard to find what I look
//! for". The sidebar lists `Section::ALL`; the search filters buttons of every category by category, card title,
//! button label, help text and field labels, without accents or case ("webhook" finds Discord > Guardar webhook).
use crate::commands::{Action, Section, ACTIONS};

/// Lower case without the accents of Portuguese, so "acoes" finds "Ações" and "configuracao" finds "configuração".
pub fn fold(s: &str) -> String {
    s.chars()
        .flat_map(char::to_lowercase)
        .map(|c| match c {
            'á' | 'à' | 'â' | 'ã' | 'ä' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'í' | 'ì' | 'î' | 'ï' => 'i',
            'ó' | 'ò' | 'ô' | 'õ' | 'ö' => 'o',
            'ú' | 'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            other => other,
        })
        .collect()
}

/// The words of a query, folded. An empty or blank query has none.
pub fn words(query: &str) -> Vec<String> {
    fold(query).split_whitespace().map(str::to_string).collect()
}

/// Everything the search reads of one button: category, card title, label, help text, field labels.
pub fn haystack(a: &Action) -> String {
    let mut h = format!("{} {} {} {}", a.section.title(), a.group, a.label, a.hint);
    for p in a.params {
        h.push(' ');
        h.push_str(p.label);
    }
    fold(&h)
}

/// True when every word is in the text (the text already folded).
fn all_in(text: &str, words: &[String]) -> bool {
    words.iter().all(|w| text.contains(w.as_str()))
}

/// The buttons of one category, in table order.
pub fn actions_of(section: Section) -> Vec<usize> {
    ACTIONS
        .iter()
        .enumerate()
        .filter(|(_, a)| a.section == section)
        .map(|(i, _)| i)
        .collect()
}

/// The groups (card titles) of a list of buttons, in first-seen order, each with its buttons.
pub fn groups(indices: &[usize]) -> Vec<(&'static str, Vec<usize>)> {
    let mut out: Vec<(&'static str, Vec<usize>)> = Vec::new();
    for &i in indices {
        let g = ACTIONS[i].group;
        match out.iter_mut().find(|(name, _)| *name == g) {
            Some((_, v)) => v.push(i),
            None => out.push((g, vec![i])),
        }
    }
    out
}

/// What one category holds for a query.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hit {
    pub section: Section,
    /// Matching buttons, in table order.
    pub actions: Vec<usize>,
    /// The category's own cards or page match (its title or `page_words`).
    pub page: bool,
}

/// The search: one hit per category with a matching button or page, in sidebar order. A blank query gives no hits
/// (the window then shows the chosen category).
pub fn search(query: &str) -> Vec<Hit> {
    let w = words(query);
    if w.is_empty() {
        return Vec::new();
    }
    Section::ALL
        .into_iter()
        .filter_map(|s| {
            let actions: Vec<usize> = actions_of(s)
                .into_iter()
                .filter(|&i| all_in(&haystack(&ACTIONS[i]), &w))
                .collect();
            let page = !s.page_words().is_empty() || actions_of(s).is_empty();
            let page = page && all_in(&fold(&format!("{} {}", s.title(), s.page_words())), &w);
            (page || !actions.is_empty()).then_some(Hit {
                section: s,
                actions,
                page,
            })
        })
        .collect()
}

/// The category to open at start: the remembered one, else Painel (Config while the app is not set up).
pub fn start_section(remembered: &str, configured: bool) -> Section {
    if !configured {
        return Section::Settings;
    }
    Section::from_key(remembered).unwrap_or(Section::Panel)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    fn titles(h: &Hit) -> Vec<String> {
        h.actions
            .iter()
            .map(|&i| format!("{} > {}", ACTIONS[i].group, ACTIONS[i].label))
            .collect()
    }

    #[test]
    fn categories_are_unique_and_none_is_empty() {
        let mut keys = HashSet::new();
        let mut names = HashSet::new();
        for s in Section::ALL {
            assert!(keys.insert(s.key()), "key {}", s.key());
            assert!(names.insert(s.title()), "title {}", s.title());
            assert_eq!(Section::from_key(s.key()), Some(s));
            // a category is either buttons or a page with its own cards (or both): never blank
            assert!(
                !actions_of(s).is_empty() || !s.page_words().is_empty(),
                "{} is empty",
                s.title()
            );
        }
        assert_eq!(Section::from_key("nope"), None);
        // every button is in a listed category, and the table runs in sidebar order (one block per category)
        let order: Vec<Section> = ACTIONS.iter().map(|a| a.section).collect();
        let mut last = 0;
        for s in order {
            let pos = Section::ALL.iter().position(|x| *x == s).expect("listed");
            assert!(pos >= last, "{} out of sidebar order", s.title());
            last = pos;
        }
    }

    #[test]
    fn the_sidebar_names_the_owners_categories() {
        let t: Vec<&str> = Section::ALL.iter().map(|s| s.title()).collect();
        for want in [
            "Painel",
            "Ao vivo",
            "Jogadores",
            "Painel do jogo",
            "Atualizações",
            "Discord",
            "Logs",
            "Config",
        ] {
            assert!(t.contains(&want), "{want}");
        }
        assert_eq!(Section::ALL[0], Section::Panel);
        assert_eq!(*Section::ALL.last().unwrap(), Section::Settings);
        assert!(actions_of(Section::LiveView).is_empty() && actions_of(Section::Settings).is_empty());
    }

    #[test]
    fn groups_keep_table_order_and_no_group_spans_two_categories() {
        for s in Section::ALL {
            let idx = actions_of(s);
            let g = groups(&idx);
            assert_eq!(g.iter().map(|(_, v)| v.len()).sum::<usize>(), idx.len());
            for (name, v) in &g {
                assert!(v.windows(2).all(|w| w[0] < w[1]));
                assert!(v.iter().all(|&i| ACTIONS[i].group == *name));
            }
        }
        // a card title belongs to one category, except the two "Par do cliente" cards (game setting and its log)
        let mut seen: Vec<(&str, Section)> = Vec::new();
        for a in ACTIONS {
            if !seen.contains(&(a.group, a.section)) {
                seen.push((a.group, a.section));
            }
        }
        let mut names: Vec<&str> = seen.iter().map(|(g, _)| *g).collect();
        names.sort_unstable();
        let mut dup: Vec<&str> = names.windows(2).filter(|w| w[0] == w[1]).map(|w| w[0]).collect();
        dup.dedup();
        assert_eq!(dup, ["Par do cliente"]);
    }

    #[test]
    fn webhook_finds_discord() {
        let h = search("webhook");
        assert_eq!(h.len(), 1, "{h:?}");
        assert_eq!(h[0].section, Section::Discord);
        assert_eq!(titles(&h[0]), ["Discord > Guardar webhook"]);
        assert!(!h[0].page);
    }

    #[test]
    fn folds_accents_and_case() {
        assert_eq!(fold("Ações ÉPICAS çà"), "acoes epicas ca");
        let a = search("ACOES RAPIDAS");
        let b = search("ações rápidas");
        assert_eq!(a, b);
        assert_eq!(a.len(), 1);
        assert_eq!(a[0].section, Section::Panel);
        assert_eq!(a[0].actions.len(), 4);
    }

    #[test]
    fn every_word_must_match() {
        let h = search("bot reiniciar");
        assert_eq!(h.len(), 1);
        assert_eq!(titles(&h[0]), ["Bot do Discord > Reiniciar"]);
        assert!(search("webhook testers").is_empty());
        assert!(search("zzzz").is_empty());
    }

    #[test]
    fn blank_query_has_no_hits() {
        assert!(search("").is_empty());
        assert!(search("   ").is_empty());
    }

    #[test]
    fn help_text_and_field_labels_count() {
        // only in a hint: "Compila com cargo na VPS"
        let h = search("cargo");
        assert_eq!(titles(&h[0]), ["Serviços de login > Rust ligado"]);
        // only in a field label: "Segundos de aviso"
        let h = search("segundos");
        let all: Vec<String> = h.iter().flat_map(titles).collect();
        assert!(all.contains(&"Servidor > Reiniciar com aviso".to_string()), "{all:?}");
    }

    #[test]
    fn pages_are_found_by_their_cards() {
        let h = search("chave");
        assert!(h.iter().any(|x| x.section == Section::Settings && x.page), "{h:?}");
        let h = search("terminal");
        assert!(h.iter().any(|x| x.section == Section::Logs && x.page));
        // a category title alone lists all its buttons
        let h = search("testers");
        let t = h.iter().find(|x| x.section == Section::Testers).unwrap();
        assert_eq!(t.actions, actions_of(Section::Testers));
        // a page-only category is found by its title
        assert!(search("ao vivo")
            .iter()
            .any(|x| x.section == Section::LiveView && x.page));
    }

    #[test]
    fn hits_follow_sidebar_order() {
        let h = search("log");
        let pos: Vec<usize> = h
            .iter()
            .map(|x| Section::ALL.iter().position(|s| *s == x.section).unwrap())
            .collect();
        assert!(pos.windows(2).all(|w| w[0] < w[1]));
        assert!(h.len() >= 4);
    }

    #[test]
    fn start_category() {
        assert_eq!(start_section("discord", true), Section::Discord);
        assert_eq!(start_section("", true), Section::Panel);
        assert_eq!(start_section("gone", true), Section::Panel);
        assert_eq!(start_section("discord", false), Section::Settings);
    }
}
