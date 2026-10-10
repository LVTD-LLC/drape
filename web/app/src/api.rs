//! The JSON API, mounted at `/api/v1` when the `api` feature is enabled.
//!
//! Requests authenticate with a personal API key (`Authorization: Bearer
//! sr_...`) that users create on the settings page. Browser sessions are
//! never accepted here, so cookies cannot be replayed cross-site, and no
//! CORS headers are sent. Every response is JSON, including errors
//! (`{"error": "..."}`) and the 404 for unknown paths.
//!
//! Two endpoints ship with every project: `GET /api/v1` describes the
//! service and `GET /api/v1/me` returns the account behind the key. Add
//! your product's endpoints to [`router`]: take [`ApiUser`] as an argument
//! to require a key, return `Result<Response, ApiError>`, and build bodies
//! with [`json_response`]. Keep business logic in your own modules and call
//! in from here, as the HTML handlers do.

use crate::{AppError, SharedState, api_keys};
use app_auth::User;
use axum::Router;
use axum::extract::{FromRequestParts, State};
use axum::http::{HeaderValue, StatusCode, header, request::Parts};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use serde_json::{Value, json};
use time::format_description::well_known::Rfc3339;

pub const BASE_PATH: &str = "/api/v1";

pub fn router() -> Router<SharedState> {
    Router::new().route("/", get(info)).route("/me", get(me)).fallback(not_found)
}

// ---------------------------------------------------------------------------
// Responses and errors
// ---------------------------------------------------------------------------

/// A JSON body with the headers every API response carries.
pub fn json_response(status: StatusCode, value: Value) -> Response {
    (
        status,
        [(header::CONTENT_TYPE, "application/json; charset=utf-8"), (header::CACHE_CONTROL, "private, no-store")],
        value.to_string(),
    )
        .into_response()
}

/// Like [`AppError`], but every outcome is a JSON object with an `error` message.
#[derive(Debug)]
pub enum ApiError {
    Status(StatusCode, String),
    Internal(anyhow::Error),
}

impl ApiError {
    pub fn status(status: StatusCode, message: impl Into<String>) -> Self {
        Self::Status(status, message.into())
    }
}

impl From<AppError> for ApiError {
    fn from(error: AppError) -> Self {
        match error {
            AppError::Internal(error) => Self::Internal(error),
            AppError::Status(status, message) => Self::Status(status, message),
        }
    }
}

impl From<anyhow::Error> for ApiError {
    fn from(error: anyhow::Error) -> Self {
        Self::Internal(error)
    }
}

impl From<sqlx::Error> for ApiError {
    fn from(error: sqlx::Error) -> Self {
        Self::Internal(error.into())
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        match self {
            // Route through AppError so logging and error reporting stay in one place,
            // then replace the plain-text body with JSON.
            Self::Internal(error) => {
                let mut response = AppError::Internal(error).into_response();
                let (parts, _) = response.into_parts();
                response = json_response(StatusCode::INTERNAL_SERVER_ERROR, json!({ "error": "internal error" }));
                *response.extensions_mut() = parts.extensions;
                response
            }
            Self::Status(status, message) => json_response(status, json!({ "error": message })),
        }
    }
}

async fn not_found() -> ApiError {
    ApiError::status(StatusCode::NOT_FOUND, "Not found.")
}

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------

/// The owner of the bearer API key. Rejects with a JSON 401; never reads cookies.
pub struct ApiUser(pub User);

fn unauthorized(message: &str) -> Response {
    let mut response = json_response(StatusCode::UNAUTHORIZED, json!({ "error": message }));
    response.headers_mut().insert(header::WWW_AUTHENTICATE, HeaderValue::from_static("Bearer"));
    response
}

impl FromRequestParts<SharedState> for ApiUser {
    type Rejection = Response;

    async fn from_request_parts(parts: &mut Parts, state: &SharedState) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get(header::AUTHORIZATION)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.trim().split_once(' '))
            .filter(|(scheme, _)| scheme.eq_ignore_ascii_case("bearer"))
            .map(|(_, token)| token.trim());
        let Some(token) = token else {
            return Err(unauthorized("Provide an API key as `Authorization: Bearer sr_...`. Create one in Settings."));
        };
        match api_keys::authenticate(&state.pool, token).await {
            Ok(Some(user)) => Ok(ApiUser(user)),
            Ok(None) => Err(unauthorized("This API key is invalid or has been revoked.")),
            Err(error) => Err(ApiError::from(error).into_response()),
        }
    }
}

// ---------------------------------------------------------------------------
// Endpoints shared by every project
// ---------------------------------------------------------------------------

/// Public: what this service is, for clients checking connectivity and version.
async fn info() -> Response {
    json_response(
        StatusCode::OK,
        json!({
            "name": crate::views::SITE_NAME,
            "version": env!("CARGO_PKG_VERSION"),
            "revision": app_core::http::BUILD_REVISION,
            "docs": if cfg!(feature = "docs") { Value::from("/docs/api") } else { Value::Null },
        }),
    )
}

/// The account behind the key.
async fn me(State(state): State<SharedState>, ApiUser(user): ApiUser) -> Result<Response, ApiError> {
    Ok(json_response(StatusCode::OK, account_json(&state, &user).await?))
}

/// The `GET /api/v1/me` document; the MCP server's `get_account` tool returns the same.
pub async fn account_json(state: &SharedState, user: &User) -> Result<Value, ApiError> {
    let profile = crate::settings::profile(&state.pool, user.id).await?;
    Ok(json!({
        "id": user.id,
        "email": profile.email,
        "name": profile.name,
        "is_admin": user.is_admin,
        "created_at": user.created_at.format(&Rfc3339).unwrap_or_default(),
    }))
}
