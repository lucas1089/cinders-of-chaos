//! Update and bug report cards of the Painel tab (O312). Pure parsing and pt-BR wording of the `chaos-ctl.sh update-check`
//! output (server/deploy/chaos_kit_update.sh) and of the `feedback` blocks (server/tools/feedback_format.py), like
//! android/.../UpdateInfo.java and FeedbackInfo.java. No I/O here.
use std::collections::BTreeMap;

/// The key=value lines of `update-check`, plus its `commit=HASH subject` lines.
#[derive(Clone, Debug, Default)]
pub struct UpdateInfo {
    kv: BTreeMap<String, String>,
    pub commits: Vec<String>,
}

impl UpdateInfo {
    pub fn parse(out: &str) -> UpdateInfo {
        let mut u = UpdateInfo::default();
        for line in out.split('\n') {
            let Some(eq) = line.find('=') else { continue };
            if eq == 0 {
                continue;
            }
            let k = line[..eq].trim();
            let v = line[eq + 1..].trim();
            if k == "commit" {
                u.commits.push(v.to_string());
            } else {
                u.kv.entry(k.to_string()).or_insert_with(|| v.to_string());
            }
        }
        u
    }

    pub fn get(&self, k: &str) -> &str {
        self.kv.get(k).map(String::as_str).unwrap_or("")
    }

    pub fn valid(&self) -> bool {
        self.kv.contains_key("update_available")
    }

    pub fn available(&self) -> bool {
        self.get("update_available") == "yes"
    }

    pub fn running(&self) -> bool {
        self.get("running") == "yes"
    }

    /// One line over the card: "Há atualização." or "Tudo em dia."
    pub fn headline(&self) -> &'static str {
        if self.available() {
            "Há atualização."
        } else {
            "Tudo em dia."
        }
    }

    /// The summary lines: code (with the new commits as "  • " lines), engine, map master, client update, downloads, site.
    pub fn summary_lines(&self) -> Vec<String> {
        let mut b: Vec<String> = Vec::new();
        let behind = num(self.get("behind"));
        let branch = if self.get("branch").is_empty() {
            "main"
        } else {
            self.get("branch")
        };
        if behind > 0 {
            b.push(format!(
                "Código: {} {} em {} ({} → {})",
                behind,
                if behind == 1 { "commit novo" } else { "commits novos" },
                branch,
                self.get("local_commit"),
                self.get("remote_commit")
            ));
            for c in &self.commits {
                b.push(format!("  • {c}"));
            }
            if behind > self.commits.len() as i64 {
                b.push(format!("  • … e mais {}", behind - self.commits.len() as i64));
            }
        } else {
            b.push(format!("Código: em dia com {} ({})", branch, self.get("local_commit")));
        }
        if num(self.get("ahead")) > 0 {
            b.push("Atenção: a VPS tem commits que não estão no GitHub; a atualização vai recusar.".into());
        }
        let inst = self.get("installed_release");
        let latest = self.get("latest_release");
        if self.get("needs_engine") == "yes" {
            let from = if inst == "unknown" {
                "versão instalada desconhecida".to_string()
            } else {
                format!("winpkg-{inst}")
            };
            b.push(format!(
                "Servidor (engine): {from} → winpkg-{latest} (baixa e troca o tfs)"
            ));
        } else if latest.is_empty() || latest == "unknown" {
            b.push("Servidor (engine): não consegui ler as releases do GitHub".into());
        } else {
            b.push(format!("Servidor (engine): em dia (winpkg-{inst})"));
        }
        let master = self.get("map_master");
        if self.get("needs_map") == "yes" {
            let im = self.get("installed_map");
            let from = if im.is_empty() || im == "0" {
                "mapa da base".to_string()
            } else {
                format!("versão {im}")
            };
            b.push(format!(
                "Mapa: {from} → versão {master} do mapa mestre (troca o mapa, com backup)"
            ));
        } else if self.get("needs_map") == "unknown" {
            b.push("Mapa: não consegui ler o mapa mestre no GitHub".into());
        } else if !master.is_empty() && master != "none" {
            b.push(format!(
                "Mapa: em dia (versão {} do mapa mestre)",
                self.get("installed_map")
            ));
        }
        let client = if self.get("needs_client") == "yes" {
            format!(" → publica {latest}")
        } else {
            " (em dia)".into()
        };
        b.push(format!(
            "Update do client: publicado {}{}",
            self.get("published_client"),
            client
        ));
        let downloads = if self.get("needs_downloads") == "yes" {
            format!(" → {latest}")
        } else {
            " (em dia)".into()
        };
        b.push(format!(
            "Downloads do site: release {}{}",
            self.get("downloads_release"),
            downloads
        ));
        b.push(format!(
            "Site: {}",
            if self.get("website_changed") == "yes" {
                "mudou, será reinstalado"
            } else {
                "sem mudanças"
            }
        ));
        b
    }

    /// The last run, from `update-check`. Empty when there is none.
    pub fn last_run(&self) -> String {
        let pick = |a: &str, b: &str| {
            if self.get(a).is_empty() {
                self.get(b).to_string()
            } else {
                self.get(a).to_string()
            }
        };
        let st = pick("last_status", "status");
        let res = pick("last_result", "result");
        let time = pick("last_time", "time");
        if st.is_empty() {
            return String::new();
        }
        let tail = if res.is_empty() {
            String::new()
        } else {
            format!(". {res}")
        };
        format!("Última vez ({}): {}{}", time, status_word(&st), tail)
    }
}

/// The status of a run of chaos_kit_update.sh in Portuguese.
pub fn status_word(st: &str) -> String {
    match st {
        "ok" => "concluída",
        "warn" => "concluída com avisos",
        "failed" => "falhou",
        "rolled-back" => "falhou e voltou à versão anterior",
        "running" => "em andamento (ou interrompida)",
        other => other,
    }
    .to_string()
}

fn num(s: &str) -> i64 {
    s.trim().parse().unwrap_or(0)
}

/// One bug report or suggestion of `feedback`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Report {
    pub id: u32,
    pub when: String,
    pub category: String,
    pub closed: bool,
    pub pos: String,
    /// "lvl 120 Mystic" or empty.
    pub who: String,
    pub text: String,
    pub closed_note: String,
}

/// Control and format characters out (the server strips them too), one line.
pub fn clean(s: &str) -> String {
    let mut b = String::new();
    for c in s.chars() {
        let format = matches!(c, '\u{ad}' | '\u{61c}' | '\u{200b}'..='\u{200f}' | '\u{202a}'..='\u{202e}'
            | '\u{2060}'..='\u{2064}' | '\u{2066}'..='\u{206f}' | '\u{feff}');
        if matches!(c, '\t' | '\r' | '\n') {
            b.push(' ');
        } else if c.is_control() || format {
            continue;
        } else {
            b.push(c);
        }
    }
    b.split(' ').filter(|p| !p.is_empty()).collect::<Vec<_>>().join(" ")
}

fn digits(s: &str, max: usize) -> bool {
    !s.is_empty() && s.len() <= max && s.bytes().all(|b| b.is_ascii_digit())
}

/// "2026-10-27 14:03 UTC"
fn is_when(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 20
        && s.ends_with(" UTC")
        && b[..16].iter().enumerate().all(|(i, c)| match i {
            4 | 7 => *c == b'-',
            10 => *c == b' ',
            13 => *c == b':',
            _ => c.is_ascii_digit(),
        })
}

/// `#12 | 2026-10-27 14:03 UTC | map | open | pos 1010,990,7[ | lvl 120 Mystic]`
fn parse_head(line: &str) -> Option<Report> {
    let p: Vec<&str> = line.splitn(6, " | ").collect();
    if p.len() < 5 {
        return None;
    }
    let id = p[0].strip_prefix('#')?;
    let cat = p[2];
    let pos = p[4].strip_prefix("pos ")?;
    let nums: Vec<&str> = pos.split(',').collect();
    let who = p.get(5).copied().unwrap_or("");
    if !digits(id, 9)
        || !is_when(p[1])
        || !(3..=12).contains(&cat.len())
        || !cat.bytes().all(|b| b.is_ascii_lowercase())
        || !matches!(p[3], "open" | "closed")
        || nums.len() != 3
        || !nums.iter().all(|n| digits(n, usize::MAX))
        || (p.len() == 6 && !(1..=60).contains(&who.chars().count()))
    {
        return None;
    }
    Some(Report {
        id: id.parse().ok()?,
        when: p[1].to_string(),
        category: cat.to_string(),
        closed: p[3] == "closed",
        pos: pos.to_string(),
        who: clean(who),
        ..Report::default()
    })
}

/// The reports of a `feedback` output, in the order printed. Lines that are no block (the footer, an error) are ignored.
/// The `from:` line is never read: the app does not ask for names.
pub fn parse_reports(out: &str) -> Vec<Report> {
    let mut list = Vec::new();
    let mut cur: Option<Report> = None;
    let mut have_text = false;
    for line in out.split('\n') {
        let line = line.replace('\r', "");
        if let Some(r) = parse_head(&line) {
            list.extend(cur.take());
            cur = Some(r);
            have_text = false;
        } else if let (Some(r), Some(body)) = (cur.as_mut(), line.strip_prefix("  ")) {
            if have_text && body.starts_with("closed: ") {
                r.closed_note = clean(&body[8..]);
            } else if !have_text {
                r.text = clean(body);
                have_text = true;
            }
        } else if line.starts_with("--") {
            list.extend(cur.take());
        }
    }
    list.extend(cur);
    list
}

pub fn category_label(c: &str) -> &'static str {
    match c {
        "map" => "Mapa",
        "typo" => "Texto errado",
        "technical" => "Técnico",
        "suggestion" => "Sugestão",
        _ => "Outro",
    }
}

/// One line over the list: "3 relatos, 2 abertos, 1 sugestão."
pub fn reports_summary(list: &[Report]) -> String {
    if list.is_empty() {
        return "Nenhum relato neste período.".into();
    }
    let open = list.iter().filter(|r| !r.closed).count();
    let sug = list.iter().filter(|r| r.category == "suggestion").count();
    format!(
        "{} {}, {} {}, {} {}.",
        list.len(),
        if list.len() == 1 { "relato" } else { "relatos" },
        open,
        if open == 1 { "aberto" } else { "abertos" },
        sug,
        if sug == 1 { "sugestão" } else { "sugestões" }
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    // Synthetic fixtures only: no real account, character or log data.
    const CHECK: &str = "branch=main\nlocal_commit=abc1234\nremote_commit=def5678\nbehind=3\nahead=0\n\
        commit=def5678 Fix the gate\ncommit=cafe001 Add depots\ninstalled_release=120\nlatest_release=123\n\
        needs_engine=yes\nmap_master=5\ninstalled_map=4\nneeds_map=yes\npublished_client=120\nneeds_client=yes\n\
        downloads_release=120\nneeds_downloads=yes\nwebsite_changed=yes\nupdate_available=yes\nrunning=no\n\
        last_status=ok\nlast_result=updated to 120\nlast_time=2026-10-20 03:00\nruns_as_root=no\n";
    const FRESH: &str = "branch=main\nlocal_commit=abc1234\nremote_commit=abc1234\nbehind=0\nahead=0\n\
        installed_release=123\nlatest_release=123\nneeds_engine=no\nmap_master=none\ninstalled_map=0\nneeds_map=no\n\
        published_client=123\nneeds_client=no\ndownloads_release=123\nneeds_downloads=no\nwebsite_changed=no\n\
        update_available=no\nrunning=no\nlast_status=\nlast_result=\nlast_time=\n";

    #[test]
    fn update_with_news() {
        let u = UpdateInfo::parse(CHECK);
        assert!(u.valid() && u.available() && !u.running());
        assert_eq!(u.headline(), "Há atualização.");
        assert_eq!(u.commits.len(), 2);
        let s = u.summary_lines();
        assert_eq!(s[0], "Código: 3 commits novos em main (abc1234 → def5678)");
        assert_eq!(s[1], "  • def5678 Fix the gate");
        assert_eq!(s[3], "  • … e mais 1");
        assert!(s.contains(&"Servidor (engine): winpkg-120 → winpkg-123 (baixa e troca o tfs)".to_string()));
        assert!(s.contains(&"Mapa: versão 4 → versão 5 do mapa mestre (troca o mapa, com backup)".to_string()));
        assert!(s.contains(&"Update do client: publicado 120 → publica 123".to_string()));
        assert!(s.contains(&"Downloads do site: release 120 → 123".to_string()));
        assert_eq!(s.last().unwrap(), "Site: mudou, será reinstalado");
        assert_eq!(u.last_run(), "Última vez (2026-10-20 03:00): concluída. updated to 120");
    }

    #[test]
    fn update_up_to_date() {
        let u = UpdateInfo::parse(FRESH);
        assert!(u.valid() && !u.available());
        assert_eq!(u.headline(), "Tudo em dia.");
        let s = u.summary_lines();
        assert_eq!(s[0], "Código: em dia com main (abc1234)");
        assert_eq!(s[1], "Servidor (engine): em dia (winpkg-123)");
        assert_eq!(s[2], "Update do client: publicado 123 (em dia)");
        assert_eq!(s.last().unwrap(), "Site: sem mudanças");
        assert_eq!(s.len(), 5, "no map line when the master is none");
        assert_eq!(u.last_run(), "");
    }

    #[test]
    fn update_odd_cases() {
        let u = UpdateInfo::parse(
            "behind=1\nahead=2\ncommit=a1 One\nneeds_engine=yes\ninstalled_release=unknown\nlatest_release=9\n\
            needs_map=unknown\nupdate_available=yes\nrunning=yes\nlast_status=rolled-back\nlast_time=t\n",
        );
        let s = u.summary_lines();
        assert_eq!(s[0], "Código: 1 commit novo em main ( → )");
        assert!(s.iter().any(|l| l.starts_with("Atenção: a VPS tem commits")));
        assert!(s.contains(
            &"Servidor (engine): versão instalada desconhecida → winpkg-9 (baixa e troca o tfs)".to_string()
        ));
        assert!(s.contains(&"Mapa: não consegui ler o mapa mestre no GitHub".to_string()));
        assert!(u.running());
        assert_eq!(u.last_run(), "Última vez (t): falhou e voltou à versão anterior");
        let n = UpdateInfo::parse(
            "needs_engine=no\nlatest_release=unknown\nneeds_map=yes\ninstalled_map=0\nmap_master=2\n",
        );
        let s = n.summary_lines();
        assert!(s.contains(&"Servidor (engine): não consegui ler as releases do GitHub".to_string()));
        assert!(s.contains(&"Mapa: mapa da base → versão 2 do mapa mestre (troca o mapa, com backup)".to_string()));
    }

    #[test]
    fn update_first_key_wins_and_errors_are_invalid() {
        let u = UpdateInfo::parse("behind=1\nbehind=9\n=x\nno equals\n");
        assert_eq!(u.get("behind"), "1");
        assert!(!u.valid());
        assert!(!UpdateInfo::parse("chaos-ctl: update-check failed").valid());
        assert!(!UpdateInfo::parse("").valid());
        assert_eq!(status_word("warn"), "concluída com avisos");
        assert_eq!(status_word("zzz"), "zzz");
    }

    const FB: &str = "#12 | 2026-10-27 14:03 UTC | map | open | pos 1010,990,7 | lvl 120 Mystic\n  Wall \\x missing near the gate\n\
        #11 | 2026-10-26 07:33 UTC | suggestion | closed | pos 1,2,7\n  more depots please\n  from: Bobby\n  closed: done; thanks\u{7}\n\
        #9 | 2026-10-25 01:00 UTC | other | open | pos 5,6,7 | lvl 8 Iron Sage\n  -\n-- 3 reports\n";

    #[test]
    fn reports_parse() {
        let l = parse_reports(FB);
        assert_eq!(l.len(), 3);
        let a = &l[0];
        assert_eq!((a.id, a.category.as_str(), a.closed), (12, "map", false));
        assert_eq!((a.pos.as_str(), a.who.as_str()), ("1010,990,7", "lvl 120 Mystic"));
        assert_eq!(a.when, "2026-10-27 14:03 UTC");
        assert_eq!(a.text, "Wall \\x missing near the gate");
        let b = &l[1];
        assert!(b.closed && b.who.is_empty());
        assert_eq!(b.closed_note, "done; thanks");
        assert!(
            !b.text.contains("Bobby") && !b.closed_note.contains("Bobby"),
            "names are never shown"
        );
        assert_eq!(l[2].text, "-");
    }

    #[test]
    fn reports_ignore_what_is_no_block() {
        assert!(parse_reports("No bug reports or suggestions.\n").is_empty());
        assert!(parse_reports("chaos-ctl: database-down: x").is_empty());
        assert!(parse_reports("").is_empty());
        assert!(parse_reports("#1 | evil\n  text\n").is_empty());
        assert!(parse_reports("#1; rm -rf | 2026-10-27 14:03 UTC | map | open | pos 1,2,3\n  x\n").is_empty());
        assert!(parse_reports("#1 | 2026-10-27 14:03 UTC | map | maybe | pos 1,2,3\n  x\n").is_empty());
        assert!(parse_reports("#1 | 2026-10-27 14:03 UTC | map | open | pos 1,2\n  x\n").is_empty());
        assert!(parse_reports("#1234567890 | 2026-10-27 14:03 UTC | map | open | pos 1,2,3\n  x\n").is_empty());
        let crlf = parse_reports("#4 | 2026-10-27 14:03 UTC | typo | open | pos 1,2,3\r\n  hi\r\n-- 1 report\r\n");
        assert_eq!(crlf.len(), 1);
        assert_eq!(crlf[0].text, "hi");
    }

    #[test]
    fn reports_wording() {
        let l = parse_reports(FB);
        assert_eq!(reports_summary(&l), "3 relatos, 2 abertos, 1 sugestão.");
        assert_eq!(reports_summary(&l[..1]), "1 relato, 1 aberto, 0 sugestões.");
        assert!(reports_summary(&[]).starts_with("Nenhum"));
        assert_eq!(category_label("technical"), "Técnico");
        assert_eq!(category_label("suggestion"), "Sugestão");
        assert_eq!(category_label("whatever"), "Outro");
        assert_eq!(clean("a\u{202e}b\t\t c\u{7}"), "ab c");
    }
}
