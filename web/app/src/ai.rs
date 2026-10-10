//! Compatibility gateway for the existing native app. Photos are never persisted.
//! Separate from ShipRust's account API: this credential is private-development only.
use axum::{
    Router,
    body::{Bytes, to_bytes},
    extract::{Request, State},
    http::{StatusCode, header},
    middleware,
    response::{IntoResponse, Response},
    routing::post,
};
use hmac::{Hmac, KeyInit, Mac};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::Sha256;
use std::{
    collections::VecDeque,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::sync::Semaphore;

const MAX_BODY: usize = 12_000_000;
const MAX_RESPONSE: usize = 40_000_000;
const UPSTREAM: &str = "https://openrouter.ai/api/v1";
const ANALYSIS_MODEL: &str = "openai/gpt-6-luna";
const IMAGE_MODEL: &str = "bytedance-seed/seedream-5-0-flash";

/// Provider credentials are deliberately not Debug/Serialize and never enter telemetry.
pub struct Config {
    key: String,
    token: String,
}
impl Config {
    pub fn from_env() -> anyhow::Result<Option<Self>> {
        Self::parse(
            std::env::var("OPENROUTER_API_KEY").unwrap_or_default(),
            std::env::var("DRAPE_DEVELOPMENT_TOKEN").unwrap_or_default(),
        )
    }
    fn parse(key: String, token: String) -> anyhow::Result<Option<Self>> {
        if key.is_empty() && token.is_empty() {
            return Ok(None);
        }
        anyhow::ensure!(!key.is_empty() && token.len() >= 32, "AI service credentials are missing or invalid");
        Ok(Some(Self { key, token }))
    }
}

pub struct Gateway {
    client: reqwest::Client,
    key: String,
    token_mac: Hmac<Sha256>,
    upstream: String,
    inflight: Semaphore,
    attempts: Mutex<VecDeque<Instant>>,
}
impl Gateway {
    pub fn new(config: Config) -> anyhow::Result<Arc<Self>> {
        let client = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(150))
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .build()?;
        let mut token_mac = Hmac::<Sha256>::new_from_slice(config.token.as_bytes())?;
        token_mac.update(b"Drape development gateway");
        Ok(Arc::new(Self {
            client,
            key: config.key,
            token_mac,
            upstream: UPSTREAM.into(),
            inflight: Semaphore::new(2),
            attempts: Mutex::new(VecDeque::new()),
        }))
    }
    fn authorized(&self, value: &str) -> bool {
        let Some(token) = value.strip_prefix("Bearer ") else {
            return false;
        };
        let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(token.as_bytes()) else {
            return false;
        };
        mac.update(b"Drape development gateway");
        // verify_slice compares MACs in constant time.
        self.token_mac.clone().verify_slice(&mac.finalize().into_bytes()).is_ok()
    }
}

/// Mounted after the browser's 64 KiB / 20 second middleware. No cookies or CORS.
pub fn router(gateway: Option<Arc<Gateway>>) -> Router {
    Router::new()
        .route("/api/v1/chat/completions", post(analyze))
        .route("/api/v1/images", post(image))
        .layer(middleware::from_fn(app_core::http::security_headers))
        .with_state(gateway)
}
async fn analyze(State(gateway): State<Option<Arc<Gateway>>>, request: Request) -> Response {
    proxy(gateway, "chat/completions", request).await
}
async fn image(State(gateway): State<Option<Arc<Gateway>>>, request: Request) -> Response {
    proxy(gateway, "images", request).await
}
fn failure(status: StatusCode, message: &'static str) -> Response {
    (status, [(header::CACHE_CONTROL, "no-store")], axum::Json(json!({"error": message}))).into_response()
}
async fn proxy(gateway: Option<Arc<Gateway>>, path: &str, request: Request) -> Response {
    let Some(gateway) = gateway else {
        return failure(StatusCode::SERVICE_UNAVAILABLE, "ai_unavailable");
    };
    let headers = request.headers();
    if !gateway.authorized(headers.get(header::AUTHORIZATION).and_then(|v| v.to_str().ok()).unwrap_or("")) {
        return failure(StatusCode::UNAUTHORIZED, "unauthorized");
    }
    if headers.contains_key(header::ORIGIN)
        || headers.get(header::CONTENT_TYPE).and_then(|v| v.to_str().ok()) != Some("application/json")
    {
        return failure(StatusCode::BAD_REQUEST, "invalid_request");
    }
    let Ok(_permit) = gateway.inflight.try_acquire() else {
        return failure(StatusCode::TOO_MANY_REQUESTS, "busy");
    };
    {
        let mut attempts = gateway.attempts.lock().expect("attempt counter not poisoned");
        let now = Instant::now();
        while attempts.front().is_some_and(|t| now.duration_since(*t) >= Duration::from_secs(3600)) {
            attempts.pop_front();
        }
        if attempts.len() >= 30 {
            return failure(StatusCode::TOO_MANY_REQUESTS, "busy");
        }
        attempts.push_back(now);
    }
    let bytes = match tokio::time::timeout(Duration::from_secs(30), to_bytes(request.into_body(), MAX_BODY)).await {
        Ok(Ok(bytes)) => bytes,
        Ok(Err(_)) => return failure(StatusCode::PAYLOAD_TOO_LARGE, "too_large"),
        Err(_) => return failure(StatusCode::BAD_REQUEST, "invalid_request"),
    };
    if !validate(path, &bytes) {
        return failure(StatusCode::BAD_REQUEST, "invalid_request");
    }
    let result = async {
        let mut response = gateway
            .client
            .post(format!("{}/{path}", gateway.upstream))
            .bearer_auth(&gateway.key)
            .header("X-OpenRouter-Title", "Drape")
            .header(header::CONTENT_TYPE, "application/json")
            .body(bytes)
            .send()
            .await
            .map_err(|_| ())?;
        let status = response.status();
        if status != StatusCode::OK {
            let status = match status.as_u16() {
                401 | 402 | 429 => status,
                _ => StatusCode::BAD_GATEWAY,
            };
            return Ok(failure(status, "ai_unavailable"));
        }
        let mut data = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(|_| ())? {
            if data.len() + chunk.len() > MAX_RESPONSE {
                return Ok(failure(StatusCode::BAD_GATEWAY, "invalid_response"));
            }
            data.extend_from_slice(&chunk);
        }
        Ok::<_, ()>(
            ([(header::CONTENT_TYPE, "application/json"), (header::CACHE_CONTROL, "no-store")], Bytes::from(data))
                .into_response(),
        )
    }
    .await;
    result.unwrap_or_else(|()| failure(StatusCode::BAD_GATEWAY, "ai_unavailable"))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Analysis {
    model: String,
    max_tokens: u32,
    provider: Value,
    messages: Vec<Message>,
    #[serde(default)]
    response_format: Option<Value>,
}
#[derive(Deserialize)]
struct Message {
    content: Vec<Part>,
}
#[derive(Deserialize)]
struct Part {
    #[serde(rename = "type")]
    kind: String,
    image_url: Option<ImageUrl>,
}
#[derive(Deserialize)]
struct ImageUrl {
    url: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ImageRequest {
    model: String,
    prompt: String,
    input_references: Vec<Part>,
    n: u32,
    resolution: String,
    aspect_ratio: String,
}
fn embedded(part: &Part) -> bool {
    part.kind == "image_url" && part.image_url.as_ref().is_some_and(|v| v.url.starts_with("data:image/jpeg;base64,"))
}
fn validate(path: &str, bytes: &[u8]) -> bool {
    match path {
        "chat/completions" => {
            let Ok(body) = serde_json::from_slice::<Analysis>(bytes) else {
                return false;
            };
            let _ = body.response_format;
            let images: Vec<_> =
                body.messages.iter().flat_map(|m| &m.content).filter(|p| p.kind == "image_url").collect();
            body.model == ANALYSIS_MODEL
                && body.max_tokens == 1800
                && body.provider == json!({"require_parameters": true, "data_collection": "deny"})
                && (1..=6).contains(&images.len())
                && images.into_iter().all(embedded)
        }
        "images" => {
            let Ok(body) = serde_json::from_slice::<ImageRequest>(bytes) else {
                return false;
            };
            body.model == IMAGE_MODEL
                && body.prompt.chars().count() <= 4000
                && body.n == 1
                && body.resolution == "1K"
                && body.aspect_ratio == "3:4"
                && body.input_references.len() == 1
                && embedded(&body.input_references[0])
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::Request as HttpRequest;
    use tower::ServiceExt;
    const TOKEN: &str = "development-credential-at-least-32-characters";
    fn analysis() -> Value {
        json!({"model": ANALYSIS_MODEL, "max_tokens":1800,
            "provider":{"require_parameters":true,"data_collection":"deny"},
            "messages":[{"role":"user","content":[{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,dGVzdA=="}}]}]})
    }
    fn image_body() -> Value {
        json!({"model":IMAGE_MODEL,"prompt":"Clean the same garment","n":1,"resolution":"1K","aspect_ratio":"3:4",
            "input_references":[{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,dGVzdA=="}}]})
    }
    fn request(path: &str, body: Value, token: &str) -> HttpRequest<axum::body::Body> {
        HttpRequest::post(path)
            .header(header::AUTHORIZATION, format!("Bearer {token}"))
            .header(header::CONTENT_TYPE, "application/json")
            .body(body.to_string().into())
            .unwrap()
    }
    type Calls = Arc<Mutex<Vec<(String, String, Value)>>>;
    async fn setup(status: StatusCode) -> (Arc<Gateway>, Calls, tokio::task::JoinHandle<()>) {
        let calls: Calls = Arc::new(Mutex::new(Vec::new()));
        let recorded = calls.clone();
        let upstream = Router::new().fallback(move |r: Request| {
            let recorded = recorded.clone();
            async move {
                let path = r.uri().path().to_string();
                let auth = r.headers()[header::AUTHORIZATION].to_str().unwrap().to_string();
                let body = to_bytes(r.into_body(), MAX_BODY).await.unwrap();
                recorded.lock().unwrap().push((path, auth, serde_json::from_slice(&body).unwrap()));
                (
                    status,
                    [(header::LOCATION, "http://127.0.0.1:1/never-follow")],
                    if status == StatusCode::OK {
                        "{\"data\":[{\"b64_json\":\"dGVzdA==\"}]}"
                    } else {
                        "private provider secret"
                    },
                )
            }
        });
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let task = tokio::spawn(async move {
            axum::serve(listener, upstream).await.unwrap();
        });
        let mut gateway =
            Gateway::new(Config::parse("provider-secret".into(), TOKEN.into()).unwrap().unwrap()).unwrap();
        Arc::get_mut(&mut gateway).unwrap().upstream = format!("http://{addr}/api/v1");
        (gateway, calls, task)
    }
    #[test]
    fn configuration_fails_closed() {
        assert!(Config::parse("".into(), "".into()).unwrap().is_none());
        assert!(Config::parse("key".into(), "short".into()).is_err());
        assert!(Config::parse("".into(), TOKEN.into()).is_err());
    }
    #[test]
    fn contracts_bound_models_settings_and_embedded_photos() {
        for (field, value) in [
            ("tools", json!([])),
            ("model", json!("expensive/model")),
            ("max_tokens", json!(999999)),
            ("provider", json!({})),
        ] {
            let mut b = analysis();
            b[field] = value;
            assert!(!validate("chat/completions", b.to_string().as_bytes()));
        }
        for b in [json!([]), json!({"messages":[null]}), json!(null)] {
            assert!(!validate("chat/completions", b.to_string().as_bytes()));
        }
        let mut b = analysis();
        b["messages"][0]["content"][0]["image_url"]["url"] = json!("https://example.com/image");
        assert!(!validate("chat/completions", b.to_string().as_bytes()));
        for (count, valid) in [(0, false), (1, true), (6, true), (7, false)] {
            let mut b = analysis();
            let photo = b["messages"][0]["content"][0].clone();
            b["messages"][0]["content"] = json!(vec![photo; count]);
            assert_eq!(validate("chat/completions", b.to_string().as_bytes()), valid);
        }
        let mut b = image_body();
        assert!(validate("images", b.to_string().as_bytes()));
        b["n"] = json!(2);
        assert!(!validate("images", b.to_string().as_bytes()));
    }
    #[tokio::test]
    async fn forwards_both_ios_contracts_once_and_replaces_credentials() {
        let (gateway, calls, task) = setup(StatusCode::OK).await;
        for (path, b) in [("chat/completions", analysis()), ("images", image_body())] {
            let response = router(Some(gateway.clone()))
                .oneshot(request(&format!("/api/v1/{path}"), b.clone(), TOKEN))
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::OK);
            assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
            assert!(response.headers().contains_key("x-deployment-revision"));
            assert_eq!(
                to_bytes(response.into_body(), MAX_RESPONSE).await.unwrap(),
                "{\"data\":[{\"b64_json\":\"dGVzdA==\"}]}"
            );
            let calls = calls.lock().unwrap();
            let call = calls.last().unwrap();
            assert_eq!(call.0, format!("/api/v1/{path}"));
            assert_eq!(call.1, "Bearer provider-secret");
            assert_eq!(call.2, b);
        }
        assert_eq!(calls.lock().unwrap().len(), 2);
        task.abort();
    }
    #[tokio::test]
    async fn rejects_unauthorized_origin_content_type_and_oversize_before_upstream() {
        let (gateway, calls, task) = setup(StatusCode::OK).await;
        let app = router(Some(gateway));
        let mut origin = request("/api/v1/images", image_body(), TOKEN);
        origin.headers_mut().insert(header::ORIGIN, "https://example.com".parse().unwrap());
        let mut content = request("/api/v1/images", image_body(), TOKEN);
        content.headers_mut().remove(header::CONTENT_TYPE);
        let mut oversized = request("/api/v1/images", image_body(), TOKEN);
        *oversized.body_mut() = vec![b' '; MAX_BODY + 1].into();
        for (r, status) in
            [(request("/api/v1/images", image_body(), "wrong"), 401), (origin, 400), (content, 400), (oversized, 413)]
        {
            assert_eq!(app.clone().oneshot(r).await.unwrap().status().as_u16(), status);
        }
        assert!(calls.lock().unwrap().is_empty());
        task.abort();
    }
    #[tokio::test]
    async fn failures_are_sanitized_without_retries_or_redirects() {
        for status in [401, 402, 429, 500, 302] {
            let (gateway, calls, task) = setup(StatusCode::from_u16(status).unwrap()).await;
            let response =
                router(Some(gateway.clone())).oneshot(request("/api/v1/images", image_body(), TOKEN)).await.unwrap();
            assert_eq!(response.status().as_u16(), if [401, 402, 429].contains(&status) { status } else { 502 });
            assert_eq!(to_bytes(response.into_body(), 1024).await.unwrap(), "{\"error\":\"ai_unavailable\"}");
            assert_eq!(calls.lock().unwrap().len(), 1);
            assert_eq!(gateway.inflight.available_permits(), 2);
            task.abort();
        }
    }
    #[tokio::test]
    async fn concurrency_and_hourly_attempt_limits_release_capacity() {
        let (gateway, calls, task) = setup(StatusCode::OK).await;
        let permit = gateway.inflight.acquire_many(2).await.unwrap();
        assert_eq!(
            router(Some(gateway.clone()))
                .oneshot(request("/api/v1/images", image_body(), TOKEN))
                .await
                .unwrap()
                .status(),
            429
        );
        drop(permit);
        gateway.attempts.lock().unwrap().extend(vec![Instant::now(); 30]);
        assert_eq!(
            router(Some(gateway.clone()))
                .oneshot(request("/api/v1/images", image_body(), TOKEN))
                .await
                .unwrap()
                .status(),
            429
        );
        assert_eq!(gateway.inflight.available_permits(), 2);
        assert!(calls.lock().unwrap().is_empty());
        gateway.attempts.lock().unwrap().clear();
        gateway.attempts.lock().unwrap().extend(vec![Instant::now() - Duration::from_secs(3601); 30]);
        assert_eq!(
            router(Some(gateway.clone()))
                .oneshot(request("/api/v1/images", image_body(), TOKEN))
                .await
                .unwrap()
                .status(),
            200
        );
        task.abort();
    }
}
