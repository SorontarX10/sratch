use crate::builtins::json_encode;
use crate::value::Val;
use std::process::Command;
use std::rc::Rc;

/// @prompt  or  @prompt %model
/// Uses Anthropic API via curl if ANTHROPIC_API_KEY is set, otherwise
/// echoes a deterministic stub so programs remain runnable offline.
pub fn llm_call(prompt: &Val, model: Option<&Val>) -> Result<Val, String> {
    let p = prompt.to_str();
    let m = model.map(|v| v.to_str()).unwrap_or_else(|| {
        std::env::var("SRATCH_MODEL").unwrap_or_else(|_| "claude-haiku-4-5".into())
    });

    let Ok(key) = std::env::var("ANTHROPIC_API_KEY") else {
        return Ok(Val::Str(Rc::new(format!("[stub:{}] {}", m, p))));
    };

    let body = build_body(&m, &p);
    let out = Command::new("curl")
        .args([
            "-sS",
            "-X", "POST",
            "https://api.anthropic.com/v1/messages",
            "-H", &format!("x-api-key: {}", key),
            "-H", "anthropic-version: 2023-06-01",
            "-H", "content-type: application/json",
            "-d", &body,
        ])
        .output()
        .map_err(|e| e.to_string())?;

    let raw = String::from_utf8_lossy(&out.stdout).into_owned();
    Ok(Val::Str(Rc::new(extract_text(&raw).unwrap_or(raw))))
}

fn build_body(model: &str, prompt: &str) -> String {
    let prompt_str = Val::Str(Rc::new(prompt.to_string()));
    format!(
        r#"{{"model":"{}","max_tokens":1024,"messages":[{{"role":"user","content":{}}}]}}"#,
        model,
        json_encode(&prompt_str),
    )
}

/// Minimal extractor — pulls the first `"text":"..."` substring out of the
/// Anthropic JSON response without dragging in a full JSON dep.
fn extract_text(s: &str) -> Option<String> {
    let key = "\"text\":\"";
    let i = s.find(key)? + key.len();
    let bytes = s.as_bytes();
    let mut out = String::new();
    let mut p = i;
    while p < bytes.len() {
        let c = bytes[p];
        if c == b'\\' && p + 1 < bytes.len() {
            let e = bytes[p + 1];
            match e {
                b'n' => out.push('\n'),
                b't' => out.push('\t'),
                b'r' => out.push('\r'),
                b'"' => out.push('"'),
                b'\\' => out.push('\\'),
                b'/' => out.push('/'),
                _ => { out.push(e as char); }
            }
            p += 2;
            continue;
        }
        if c == b'"' { return Some(out); }
        out.push(c as char);
        p += 1;
    }
    Some(out)
}

