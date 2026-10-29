//! The in-game admin panel: the catalog answer of `chaos-ctl.sh catalog ACTOR` and the answer of `panel ...`.
use serde_json::{json, Map, Value};

#[derive(Clone, Debug)]
pub struct PanelParam {
    pub name: String,
    pub label: String,
    /// string, int, bool, select, ...
    pub ptype: String,
    pub required: bool,
    pub options: Vec<(String, String)>,
}

#[derive(Clone, Debug)]
pub struct PanelAction {
    pub cat: String,
    pub id: String,
    pub name: String,
    pub description: String,
    pub params: Vec<PanelParam>,
    pub risky: bool,
    pub dangerous: bool,
}

/// Cuts the JSON object out of an answer that may have text before it.
fn json_part(text: &str) -> Option<Value> {
    let t = text.trim();
    serde_json::from_str(&t[t.find('{')?..]).ok()
}

pub fn parse_catalog(text: &str) -> Result<(Vec<PanelAction>, i64), String> {
    let v = json_part(text).ok_or("the game did not answer with the list")?;
    let group = v.get("group").and_then(Value::as_i64).unwrap_or(0);
    let cats = v
        .get("categories")
        .and_then(Value::as_array)
        .ok_or("no categories in the answer")?;
    let mut out = Vec::new();
    for c in cats {
        let cat = c
            .get("label")
            .or_else(|| c.get("id"))
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        for a in c.get("actions").and_then(Value::as_array).into_iter().flatten() {
            let s = |k: &str| a.get(k).and_then(Value::as_str).unwrap_or("").to_string();
            let b = |k: &str| a.get(k).and_then(Value::as_bool).unwrap_or(false);
            let mut params = Vec::new();
            for p in a.get("params").and_then(Value::as_array).into_iter().flatten() {
                let ps = |k: &str| p.get(k).and_then(Value::as_str).unwrap_or("").to_string();
                let options = p
                    .get("options")
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .map(|o| match o {
                        Value::String(x) => (x.clone(), x.clone()),
                        _ => {
                            let val = o.get("value").map(|x| x.to_string().trim_matches('"').to_string());
                            let val = val.unwrap_or_default();
                            let label = o.get("label").and_then(Value::as_str).unwrap_or(&val).to_string();
                            (val, label)
                        }
                    })
                    .collect();
                params.push(PanelParam {
                    name: ps("name"),
                    label: if ps("label").is_empty() {
                        ps("name")
                    } else {
                        ps("label")
                    },
                    ptype: if ps("type").is_empty() {
                        "string".into()
                    } else {
                        ps("type")
                    },
                    required: p.get("required").and_then(Value::as_bool).unwrap_or(false),
                    options,
                });
            }
            out.push(PanelAction {
                cat: cat.clone(),
                id: s("id"),
                name: s("name"),
                description: s("description"),
                params,
                risky: b("confirm") || b("dangerous"),
                dangerous: b("dangerous"),
            });
        }
    }
    Ok((out, group))
}

/// The JSON object sent to `panel`: typed by the parameter type; empty optional values are left out.
pub fn build_params(action: &PanelAction, values: &[String]) -> Result<String, String> {
    let mut m = Map::new();
    for (p, v) in action.params.iter().zip(values) {
        let v = v.trim();
        if v.is_empty() {
            if p.required && p.ptype != "bool" {
                return Err(format!("{}: obrigatório", p.label));
            }
            if p.ptype != "bool" {
                continue;
            }
        }
        let val = match p.ptype.as_str() {
            "bool" => json!(v == "true"),
            "int" => json!(v
                .parse::<i64>()
                .map_err(|_| format!("{}: precisa ser um número inteiro", p.label))?),
            _ => json!(v),
        };
        m.insert(p.name.clone(), val);
    }
    Ok(Value::Object(m).to_string())
}

/// Text of the answer of `panel`: (ok, message and lines).
pub fn parse_panel_result(text: &str) -> (bool, String) {
    match json_part(text) {
        Some(v) => {
            let mut s = v.get("message").and_then(Value::as_str).unwrap_or("").to_string();
            for l in v.get("lines").and_then(Value::as_array).into_iter().flatten() {
                s.push('\n');
                s.push_str(l.as_str().unwrap_or(""));
            }
            (
                v.get("ok").and_then(Value::as_bool).unwrap_or(false),
                s.trim().to_string(),
            )
        }
        None => (false, text.trim().to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CAT: &str = r#"noise {"group":5,"categories":[{"id":"srv","label":"Server","actions":[
      {"id":"reload","name":"Reload system","description":"d","dangerous":true,
       "params":[{"name":"system","label":"System","type":"select","options":[{"value":"scripts","label":"Scripts"}]}]},
      {"id":"kick","name":"Kick","params":[{"name":"who","type":"string","required":true},{"name":"n","type":"int"},{"name":"f","type":"bool"}]}]}]}"#;

    #[test]
    fn parses_catalog() {
        let (acts, group) = parse_catalog(CAT).unwrap();
        assert_eq!(group, 5);
        assert_eq!(acts.len(), 2);
        assert_eq!(acts[0].cat, "Server");
        assert!(acts[0].dangerous && acts[0].risky);
        assert_eq!(
            acts[0].params[0].options,
            vec![("scripts".to_string(), "Scripts".to_string())]
        );
        assert!(parse_catalog("nothing").is_err());
    }

    #[test]
    fn builds_typed_params() {
        let (acts, _) = parse_catalog(CAT).unwrap();
        let k = &acts[1];
        assert_eq!(
            build_params(k, &["Bob".into(), "".into(), "true".into()]).unwrap(),
            r#"{"f":true,"who":"Bob"}"#
        );
        assert!(build_params(k, &["".into(), "".into(), "".into()]).is_err());
        assert!(build_params(k, &["Bob".into(), "x".into(), "".into()]).is_err());
        assert_eq!(
            build_params(k, &["Bob".into(), "7".into(), "".into()]).unwrap(),
            r#"{"f":false,"n":7,"who":"Bob"}"#
        );
    }

    #[test]
    fn parses_result() {
        assert_eq!(
            parse_panel_result(r#"{"ok":true,"message":"Done","lines":["a","b"]}"#),
            (true, "Done\na\nb".to_string())
        );
        assert_eq!(parse_panel_result("boom"), (false, "boom".to_string()));
    }
}
