use crate::builtins::json_encode;
use crate::value::Val;
use std::process::Command;
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};

static MOCK_IDX: AtomicUsize = AtomicUsize::new(0);
static TU_IDX: AtomicUsize = AtomicUsize::new(0);

/// One step of a native tool-use exchange.
pub enum ToolReply {
    /// Final assistant text — the loop ends.
    Text(String),
    /// The model wants tool `name` invoked with the given string input.
    Call(String, String),
}

/// One round of structured tool-use. `history` is the running transcript,
/// `tool_names` the registered tool names (sent as the API tools schema).
///
/// Mock mode (SRATCH_MOCK, `\n---\n`-separated, cycled independently of @):
///   "CALL <name> <input...>"  -> ToolReply::Call
///   "DONE:<text>"             -> ToolReply::Text
/// Real mode (ANTHROPIC_API_KEY): Anthropic Messages tools API; a
/// `tool_use` content block becomes Call, otherwise the text is returned.
pub fn llm_tooluse(history: &str, tool_names: &[String]) -> Result<ToolReply, String> {
    if let Ok(mock) = std::env::var("SRATCH_MOCK") {
        let parts: Vec<&str> = mock.split("\n---\n").collect();
        if !parts.is_empty() {
            let i = TU_IDX.fetch_add(1, Ordering::SeqCst) % parts.len();
            let r = parts[i];
            if let Some(rest) = r.strip_prefix("CALL ") {
                let mut it = rest.splitn(2, ' ');
                let name = it.next().unwrap_or("").to_string();
                let input = it.next().unwrap_or("").to_string();
                return Ok(ToolReply::Call(name, input));
            }
            if let Some(t) = r.strip_prefix("DONE:") {
                return Ok(ToolReply::Text(t.to_string()));
            }
            return Ok(ToolReply::Text(r.to_string()));
        }
    }

    let model = std::env::var("SRATCH_MODEL").unwrap_or_else(|_| "claude-haiku-4-5".into());
    let Ok(key) = std::env::var("ANTHROPIC_API_KEY") else {
        return Ok(ToolReply::Text(format!("[stub:{}] {}", model, history)));
    };
    let base = std::env::var("ANTHROPIC_BASE_URL")
        .unwrap_or_else(|_| "https://api.anthropic.com".into());
    let tools: Vec<String> = tool_names.iter().map(|n| format!(
        r#"{{"name":{},"description":"sratch tool","input_schema":{{"type":"object","properties":{{"input":{{"type":"string"}}}},"required":["input"]}}}}"#,
        json_encode(&Val::Str(Rc::new(n.clone())))
    )).collect();
    let body = format!(
        r#"{{"model":"{}","max_tokens":1024,"tools":[{}],"messages":[{{"role":"user","content":{}}}]}}"#,
        model, tools.join(","), json_encode(&Val::Str(Rc::new(history.to_string()))),
    );
    let out = Command::new("curl")
        .args([
            "-sS", "-X", "POST", &format!("{}/v1/messages", base),
            "-H", &format!("x-api-key: {}", key),
            "-H", "anthropic-version: 2023-06-01",
            "-H", "content-type: application/json",
            "-d", &body,
        ])
        .output().map_err(|e| e.to_string())?;
    let raw = String::from_utf8_lossy(&out.stdout).into_owned();
    // tool_use block? pull "name" and the input string.
    if let Some(name) = extract_text(&raw, "\"type\":\"tool_use\",\"id\":\"")
        .and(extract_text(&raw, "\"name\":\""))
    {
        let input = extract_text(&raw, "\"input\":{\"input\":\"").unwrap_or_default();
        return Ok(ToolReply::Call(name, input));
    }
    Ok(ToolReply::Text(extract_text(&raw, "\"text\":\"").unwrap_or(raw)))
}

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

    let cache = std::env::var("SRATCH_CACHE").is_ok();
    if is_openai(&m) {
        // OpenAI caches automatically; no per-request marker.
        openai_call(&m, &build_messages(prompt, false), prompt)
    } else {
        anthropic_call(&m, &build_messages(prompt, cache), prompt)
    }
}

/// Builds the `"messages"` JSON array body from either a single prompt
/// string (one user message) or a Val::List of alternating user/assistant
/// strings (multi-turn). When `cache` is set, the final message's content
/// becomes a text block tagged with cache_control so Anthropic prompt-
/// caches everything up to it.
pub fn build_messages(p: &Val, cache: bool) -> String {
    let msgs: Vec<(&'static str, String)> = match p {
        Val::List(l) => {
            let items = l.borrow();
            items.iter().enumerate().map(|(i, m)| {
                let role = if i % 2 == 0 { "user" } else { "assistant" };
                (role, m.to_str())
            }).collect()
        }
        other => vec![("user", other.to_str())],
    };
    let n = msgs.len();
    let parts: Vec<String> = msgs.iter().enumerate().map(|(i, (role, text))| {
        let last = i + 1 == n;
        if cache && last {
            format!(
                r#"{{"role":"{}","content":[{{"type":"text","text":{},"cache_control":{{"type":"ephemeral"}}}}]}}"#,
                role, json_encode(&Val::Str(Rc::new(text.clone()))),
            )
        } else {
            format!(r#"{{"role":"{}","content":{}}}"#, role, json_encode(&Val::Str(Rc::new(text.clone()))))
        }
    }).collect();
    parts.join(",")
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
    let body = format!(r#"{{"model":"{}","max_tokens":1024,"messages":[{}]}}"#, model, msgs);
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
