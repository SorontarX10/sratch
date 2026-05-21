use crate::builtins::json_encode;
use crate::value::Val;
use std::process::Command;
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};

static MOCK_IDX: AtomicUsize = AtomicUsize::new(0);

/// @prompt  or  @prompt %model
///
/// Provider dispatch is by model-name prefix:
///   gpt-* / o1* / o3* / o4* / chatgpt* / text-*   -> OpenAI
///   everything else (default claude-haiku-4-5)    -> Anthropic
///
/// Resolution order:
///   1. SRATCH_MOCK       — scripted replies for testing
///   2. provider API call via curl when its key env var is set
///   3. fallthrough stub  — keeps programs runnable offline
pub fn llm_call(prompt: &Val, model: Option<&Val>) -> Result<Val, String> {
    let m = model.map(|v| v.to_str()).unwrap_or_else(|| {
        std::env::var("SRATCH_MODEL").unwrap_or_else(|_| "claude-haiku-4-5".into())
    });

    if let Ok(mock) = std::env::var("SRATCH_MOCK") {
        let parts: Vec<&str> = mock.split("\n---\n").collect();
        if !parts.is_empty() {
            let i = MOCK_IDX.fetch_add(1, Ordering::SeqCst) % parts.len();
            return Ok(Val::Str(Rc::new(parts[i].to_string())));
        }
    }

    let msgs = build_messages(prompt);
    if is_openai(&m) {
        openai_call(&m, &msgs, prompt)
    } else {
        anthropic_call(&m, &msgs, prompt)
    }
}

/// Builds the `"messages"` JSON array body from either a single prompt
/// string (one user message) or a Val::List of alternating user/assistant
/// strings (multi-turn).
fn build_messages(p: &Val) -> String {
    match p {
        Val::List(l) => {
            let items = l.borrow();
            let mut parts: Vec<String> = Vec::with_capacity(items.len());
            for (i, m) in items.iter().enumerate() {
                let role = if i % 2 == 0 { "user" } else { "assistant" };
                let content = json_encode(&Val::Str(Rc::new(m.to_str())));
                parts.push(format!(r#"{{"role":"{}","content":{}}}"#, role, content));
            }
            parts.join(",")
        }
        other => {
            let content = json_encode(&Val::Str(Rc::new(other.to_str())));
            format!(r#"{{"role":"user","content":{}}}"#, content)
        }
    }
}

fn is_openai(m: &str) -> bool {
    let l = m.to_lowercase();
    l.starts_with("gpt-")
        || l.starts_with("gpt5")
        || l.starts_with("o1")
        || l.starts_with("o3")
        || l.starts_with("o4")
        || l.starts_with("chatgpt")
        || l.starts_with("text-")
}

fn anthropic_call(model: &str, msgs: &str, original: &Val) -> Result<Val, String> {
    let Ok(key) = std::env::var("ANTHROPIC_API_KEY") else {
        return Ok(Val::Str(Rc::new(format!("[stub:{}] {}", model, original.to_str()))));
    };
    let base = std::env::var("ANTHROPIC_BASE_URL")
        .unwrap_or_else(|_| "https://api.anthropic.com".into());
    let body = format!(
        r#"{{"model":"{}","max_tokens":1024,"messages":[{}]}}"#,
        model, msgs,
    );
    let out = Command::new("curl")
        .args([
            "-sS", "-X", "POST",
            &format!("{}/v1/messages", base),
            "-H", &format!("x-api-key: {}", key),
            "-H", "anthropic-version: 2023-06-01",
            "-H", "content-type: application/json",
            "-d", &body,
        ])
        .output()
        .map_err(|e| e.to_string())?;
    let raw = String::from_utf8_lossy(&out.stdout).into_owned();
    Ok(Val::Str(Rc::new(extract_text(&raw, "\"text\":\"").unwrap_or(raw))))
}

fn openai_call(model: &str, msgs: &str, original: &Val) -> Result<Val, String> {
    let Ok(key) = std::env::var("OPENAI_API_KEY") else {
        return Ok(Val::Str(Rc::new(format!("[stub:{}] {}", model, original.to_str()))));
    };
    let base = std::env::var("OPENAI_BASE_URL")
        .unwrap_or_else(|_| "https://api.openai.com".into());
    let body = format!(
        r#"{{"model":"{}","messages":[{}]}}"#,
        model, msgs,
    );
    let out = Command::new("curl")
        .args([
            "-sS", "-X", "POST",
            &format!("{}/v1/chat/completions", base),
            "-H", &format!("authorization: Bearer {}", key),
            "-H", "content-type: application/json",
            "-d", &body,
        ])
        .output()
        .map_err(|e| e.to_string())?;
    let raw = String::from_utf8_lossy(&out.stdout).into_owned();
    Ok(Val::Str(Rc::new(extract_text(&raw, "\"content\":\"").unwrap_or(raw))))
}

/// Pulls the first `<key>...` substring out of a JSON response, decoding
/// the common escape sequences. Used for both Anthropic (`"text":"`) and
/// OpenAI (`"content":"`) without dragging in a full JSON dep.
fn extract_text(s: &str, key: &str) -> Option<String> {
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
