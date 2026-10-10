+++
title = "MCP server"
slug = "mcp"
description = "Let coding agents call your product as tools over the Model Context Protocol, with the same API keys."
section = "developer-tools"
order = 11
+++

## What is included

With the `mcp` Cargo feature (on by default, and it needs `api`), the app serves a [Model Context Protocol](https://modelcontextprotocol.io) server at `/mcp`. Agents such as Claude Code and Cursor connect to it and get your product's operations as tools they call themselves.

One tool ships with every project:

| Tool | What it does |
| --- | --- |
| `get_account` | The account behind the key: id, email, name, admin flag and join date. The same document as `GET /api/v1/me`. |

The protocol core lives in `crates/core/src/mcp.rs` and is upgraded in place with Drape releases; `app/src/mcp.rs` is yours and only describes the tools.

## Connect an agent

Create a personal API key in **Settings** (see the [API guide](/docs/api)) and give it to the agent as a bearer header. For Claude Code:

```sh
claude mcp add --transport http my-app https://example.com/mcp \
  --header "Authorization: Bearer $API_KEY"
```

Cursor and other clients with a `mcp.json` file use the same shape:

```json
{
  "mcpServers": {
    "my-app": {
      "url": "https://example.com/mcp",
      "headers": { "Authorization": "Bearer sr_..." }
    }
  }
}
```

Every tool runs as the account that owns the key. Revoking the key in Settings disconnects the agent on its next call. Browser sessions are never accepted, so cookies cannot be replayed from another site.

## Add your own tools

`app/src/mcp.rs` has two places to edit. `tools()` is the list the model reads, so describe each tool for a model: what it returns and when to use it, with a JSON Schema for its arguments. `call()` runs the tool. Keep SQL and business rules in your own modules and scope every query by `user.id`, exactly as the API handlers do.

```rust
pub fn tools() -> Vec<Value> {
    vec![
        // get_account ...
        json!({
            "name": "list_widgets",
            "title": "List widgets",
            "description": "The account's widgets, newest first. Use it before updating or deleting a widget.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "limit": { "type": "integer", "minimum": 1, "maximum": 100, "default": 20 }
                },
                "additionalProperties": false
            },
            "annotations": { "readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false }
        }),
    ]
}

async fn call(state: &SharedState, user: &User, name: &str, arguments: Value) -> Result<Option<Value>, ApiError> {
    Ok(Some(match name {
        "get_account" => { /* ... */ }
        "list_widgets" => {
            let limit = arguments["limit"].as_u64().unwrap_or(20).min(100);
            let widgets = crate::widgets::list_for_user(&state.pool, user.id, limit).await?;
            tool_result(format!("{} widgets.", widgets.len()), json!({ "widgets": widgets }))
        }
        _ => return Ok(None),
    }))
}
```

Return `tool_result(text, structured)` on success: the text is what the model reads, the structured value is the same data for clients that keep it. For a failure the model can fix, such as invalid arguments or a widget that is not the caller's, return `Err(ApiError::status(StatusCode::UNPROCESSABLE_ENTITY, "..."))`; it becomes a tool result with `isError: true` and the status, so the model can retry with better input. Any other error is logged, reported to your error tracking and answered as a JSON-RPC internal error. Mark tools that change or delete data with `destructiveHint: true` so agents ask before calling them.

## Protocol details

The server speaks MCP protocol versions `2025-06-18`, `2025-03-26` and `2024-11-05` over the Streamable HTTP transport in its stateless form: every JSON-RPC message is one `POST /mcp` answered with JSON, there are no sessions and no server-sent event stream, and `GET /mcp` returns `405`. It offers tools only. The route sits under the same body limit and timeout as the rest of the app. Large results belong behind a URL the agent can fetch, not inside a tool result, where they would land in the model's context window.

## Turn it off

Remove `"mcp"` from the default features in `app/Cargo.toml`. The route and the settings link disappear; API keys keep working for the JSON API.
