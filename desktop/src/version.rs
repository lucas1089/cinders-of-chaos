//! Version compare for the updater: "1.2.3", "v1.2.3" and "admin-desktop-v1.2.3" tags.

/// Parses the last dotted number run of a tag: "admin-desktop-v1.2.3" gives [1, 2, 3].
pub fn parse(tag: &str) -> Option<Vec<u64>> {
    let start = tag.find(|c: char| c.is_ascii_digit())?;
    let rest = &tag[start..];
    let end = rest
        .find(|c: char| !(c.is_ascii_digit() || c == '.'))
        .unwrap_or(rest.len());
    let mut out = Vec::new();
    for part in rest[..end].split('.') {
        if part.is_empty() {
            return None;
        }
        out.push(part.parse().ok()?);
    }
    Some(out)
}

/// True when `candidate` is strictly newer than `current`. Missing parts count as 0. Unparseable: false.
pub fn is_newer(candidate: &str, current: &str) -> bool {
    let (Some(mut a), Some(mut b)) = (parse(candidate), parse(current)) else {
        return false;
    };
    let n = a.len().max(b.len());
    a.resize(n, 0);
    b.resize(n, 0);
    a > b
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_tags() {
        assert_eq!(parse("1.2.3"), Some(vec![1, 2, 3]));
        assert_eq!(parse("v0.10.0"), Some(vec![0, 10, 0]));
        assert_eq!(parse("admin-desktop-v2.0"), Some(vec![2, 0]));
        assert_eq!(parse("winpkg"), None);
        assert_eq!(parse("1..2"), None);
    }

    #[test]
    fn compares_numerically() {
        assert!(is_newer("0.10.0", "0.9.9"));
        assert!(is_newer("admin-desktop-v1.0.1", "1.0.0"));
        assert!(is_newer("1.0.0.1", "1.0.0"));
        assert!(!is_newer("1.0", "1.0.0"));
        assert!(!is_newer("0.9.0", "0.10.0"));
        assert!(!is_newer("junk", "1.0.0"));
    }
}
