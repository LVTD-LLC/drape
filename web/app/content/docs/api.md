+++
title = "Setup API"
slug = "api"
description = "Give your users a way to interact with your platform through an API, with personal API keys and your own endpoints."
section = "developer-tools"
order = 10
+++

## What is included

With the `api` Cargo feature (on by default), every account can create personal API keys in **Settings**, and the app serves a JSON API at `/api/v1`:

| Method and path | Purpose |
| --- | --- |
| `GET /api/v1` | Service name, version, deployment revision and the docs link. No key required. |
| `GET /api/v1/me` | The account behind the key: id, email, name, admin flag and join date. |

Unknown paths under `/api/v1` return a JSON 404. Every error is a JSON object with an `error` message and a matching status code: `401` for a missing, invalid or revoked key, `404` for unknown resources and `500` for unexpected failures.

## Create and use a key

Open **Settings**, find **API keys**, give the key a name and select **Create API key**. The full key is shown once, so copy it into your environment. The page keeps only a short prefix; Postgres stores a SHA-256 hash. Each account can hold ten keys, revoking takes effect on the next request, and deleting the account deletes its keys.

Send the key as a bearer token:

```
curl https://example.com/api/v1/me \
  -H "Authorization: Bearer $API_KEY"
```

Browser sessions are not accepted by the API, and the API sends no CORS headers, so neither cookies nor keys can be used from another website.

## Add your own endpoints

`app/src/api.rs` owns the router. Add a route, take `ApiUser` as an argument to require a key, return `Result<Response, ApiError>` and build bodies with `json_response`:

```rust
pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/", get(info))
        .route("/me", get(me))
        .route("/widgets", get(list_widgets))
        .fallback(not_found)
}

async fn list_widgets(State(state): State<SharedState>, ApiUser(user): ApiUser) -> Result<Response, ApiError> {
    let widgets = crate::widgets::list_for_user(&state.pool, user.id).await?;
    Ok(json_response(StatusCode::OK, json!({ "widgets": widgets })))
}
```

Keep SQL and business rules in your own modules, as the HTML handlers do, and scope every query by `user.id` so one account can never read another's data. Use `ApiError::status(StatusCode::UNPROCESSABLE_ENTITY, "...")` for validation failures; any other error is logged and becomes a JSON 500. Request bodies are limited to 64 KB and requests time out after 20 seconds, like the rest of the app.

## Turn it off

Remove `"api"` from the default features in `app/Cargo.toml`. The routes, the settings panel and the `serde_json` dependency disappear; the `api_keys` table stays in the schema so the feature can be enabled again without a migration.
