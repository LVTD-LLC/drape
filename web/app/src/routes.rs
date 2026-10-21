//! HTTP routing and handlers.

use crate::AppError;
use crate::views::{self, Page};
use crate::{SharedState, assets, errors};
use app_auth::{CurrentUser, MaybeUser, sessions, users};
use app_core::http::{same_origin_guard, security_headers};
use axum::Router;
use axum::extract::{Form, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::middleware;
use axum::response::{Html, IntoResponse, Redirect, Response};
use axum::routing::{get, post};
use maud::Markup;
use serde::Deserialize;
use std::time::Duration;
use time::Duration as TimeDuration;
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::timeout::TimeoutLayer;
use tower_http::trace::TraceLayer;

pub fn router(state: SharedState) -> Router {
    let router = Router::new()
        .route("/", get(home))
        .route("/sitemap.xml", get(sitemap))
        .route("/sign-up", get(sign_up_page).post(sign_up))
        .route("/verify-email", get(verify_email_page).post(verify_email))
        .route("/verify-email/resend", post(resend_verification))
        .route("/sign-in", get(sign_in_page).post(sign_in))
        .route(
            crate::two_factor::SIGN_IN_PATH,
            get(crate::two_factor::challenge_get).post(crate::two_factor::challenge_post),
        )
        .route("/sign-out", post(sign_out))
        .route("/passkeys/register/options", post(crate::passkeys::register_options))
        .route("/passkeys/register", post(crate::passkeys::register))
        .route("/passkeys/sign-in/options", post(crate::passkeys::sign_in_options))
        .route("/passkeys/sign-in", post(crate::passkeys::sign_in))
        .route("/dashboard", get(dashboard))
        .route("/admin", get(crate::admin::page))
        .route("/settings", get(crate::settings::page).post(crate::settings::submit))
        .route(
            crate::two_factor::SETTINGS_PATH,
            get(crate::two_factor::settings_page).post(crate::two_factor::settings_submit),
        )
        .route("/healthz", get(healthz))
        .route("/assets/{*path}", get(assets::serve))
        .fallback(not_found);
    #[cfg(feature = "stripe")]
    let router = router
        .route("/billing", get(billing_page).post(start_checkout))
        .route("/billing/success", get(billing_success))
        .route("/billing/portal", post(billing_portal));
    #[cfg(feature = "api")]
    let router = router.nest(crate::api::BASE_PATH, crate::api::router());
    // Stateless MCP: POST only; axum answers other methods with 405, as the protocol allows.
    #[cfg(feature = "mcp")]
    let router = router.route(crate::mcp::PATH, post(crate::mcp::handle));
    // Browser POSTs require same-origin; only the signed webhook is exempt.
    let router = router.layer(middleware::from_fn(same_origin_guard(state.cfg.site_url.clone())));
    #[cfg(feature = "stripe")]
    let router = router.route("/stripe/webhook", post(stripe_webhook));
    #[cfg(feature = "blog")]
    let router = router
        .route("/blog", get(blog_index))
        .route("/blog/rss.xml", get(blog_feed))
        .route("/blog/{slug}", get(blog_article));
    #[cfg(feature = "docs")]
    let router = router.route("/docs", get(docs_index)).route("/docs/{slug}", get(docs_article));
    // Forms are small. The one multipart upload gets its own, larger limit.
    let router = router.layer(RequestBodyLimitLayer::new(64 * 1024));
    #[cfg(feature = "storage")]
    let router = router
        .merge(
            Router::new()
                .route("/settings/avatar", post(crate::avatars::upload))
                .layer(axum::extract::DefaultBodyLimit::max(crate::avatars::BODY_LIMIT))
                .layer(middleware::from_fn(same_origin_guard(state.cfg.site_url.clone()))),
        )
        .route("/avatars/{*path}", get(crate::avatars::serve));
    #[cfg(any(feature = "posthog-logs", feature = "posthog-traces", feature = "sentry-server"))]
    let router = router.layer(middleware::from_fn_with_state(state.clone(), crate::observability::request));
    #[cfg(feature = "sentry-server")]
    let router = router.layer(middleware::from_fn_with_state(state.clone(), crate::sentry::request));
    let ai = crate::ai::router(state.ai.clone());
    router
        .layer(middleware::from_fn_with_state(state.clone(), auth_origin))
        .layer(middleware::from_fn(security_headers))
        .layer(TraceLayer::new_for_http())
        .layer(TimeoutLayer::with_status_code(StatusCode::REQUEST_TIMEOUT, Duration::from_secs(20)))
        .with_state(state)
        .merge(ai)
}

pub(crate) fn html(status: StatusCode, markup: Markup) -> Response {
    (status, [(header::CACHE_CONTROL, "private, no-store")], Html(markup.into_string())).into_response()
}

// ---------------------------------------------------------------------------
// Pages
// ---------------------------------------------------------------------------

async fn home(State(state): State<SharedState>, MaybeUser(user): MaybeUser) -> Response {
    let page = Page { title: "Your personal wardrobe", path: "/", user: user.as_ref(), body: views::pages::home() };
    html(StatusCode::OK, views::layout(&state, page))
}

async fn dashboard(State(state): State<SharedState>, CurrentUser(user): CurrentUser) -> Response {
    #[cfg(feature = "posthog")]
    crate::analytics::record_user(&user);
    let page = Page { title: "Dashboard", path: "/dashboard", user: Some(&user), body: views::pages::dashboard(&user) };
    html(StatusCode::OK, views::layout(&state, page))
}

async fn not_found(
    State(state): State<SharedState>,
    MaybeUser(user): MaybeUser,
    headers: HeaderMap,
) -> Result<Response, AppError> {
    Ok(errors::not_found(&headers, || {
        let page = Page { title: "Not found", path: "", user: user.as_ref(), body: views::pages::not_found() };
        html(StatusCode::NOT_FOUND, views::layout(&state, page))
    }))
}

async fn healthz() -> axum::Json<serde_json::Value> {
    axum::Json(serde_json::json!({"status": "ok", "mode": "private-development",
        "revision": app_core::http::BUILD_REVISION}))
}

async fn sitemap(State(state): State<SharedState>) -> Result<Response, AppError> {
    Ok((
        [(header::CONTENT_TYPE, "application/xml; charset=utf-8"), (header::CACHE_CONTROL, "public, max-age=3600")],
        state.sitemap.clone(),
    )
        .into_response())
}

#[cfg(feature = "blog")]
async fn blog_index(State(state): State<SharedState>, MaybeUser(user): MaybeUser) -> Result<Response, AppError> {
    let page = Page { title: "Blog", path: "/blog", user: user.as_ref(), body: views::blog::index(&state.blog) };
    Ok(html(StatusCode::OK, views::layout_with_metadata(&state, page, Some(crate::blog::DESCRIPTION), None)))
}

#[cfg(feature = "blog")]
async fn blog_article(
    State(state): State<SharedState>,
    MaybeUser(user): MaybeUser,
    axum::extract::Path(slug): axum::extract::Path<String>,
    headers: HeaderMap,
) -> Result<Response, AppError> {
    let Some(post) = state.blog.posts.iter().find(|post| post.slug == slug) else {
        return not_found(State(state), MaybeUser(user), headers).await;
    };
    let page = Page { title: &post.title, path: &post.path, user: user.as_ref(), body: views::blog::article(post) };
    Ok(html(
        StatusCode::OK,
        views::layout_with_metadata(&state, page, Some(&post.description), Some((&post.author, post.date))),
    ))
}

#[cfg(feature = "blog")]
async fn blog_feed(State(state): State<SharedState>) -> Result<Response, AppError> {
    Ok((
        [(header::CONTENT_TYPE, "application/rss+xml; charset=utf-8"), (header::CACHE_CONTROL, "public, max-age=3600")],
        state.blog.rss.clone(),
    )
        .into_response())
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct Credentials {
    pub email: String,
    pub password: String,
}

pub(crate) fn auth_page(state: &SharedState, kind: views::pages::AuthKind, email: &str, error: Option<&str>) -> Markup {
    let (title, path) = match kind {
        views::pages::AuthKind::SignUp => ("Create your account", "/sign-up"),
        views::pages::AuthKind::SignIn => ("Sign in", "/sign-in"),
    };
    let body = maud::html! {
        (views::pages::auth(kind, email, error))
        @if kind == views::pages::AuthKind::SignIn { script defer src=(state.asset_url("passkeys.js")) {} }
    };
    views::layout(state, Page { title, path, user: None, body })
}

async fn sign_up_page(State(state): State<SharedState>, MaybeUser(user): MaybeUser) -> Response {
    if user.is_some() {
        return Redirect::to("/dashboard").into_response();
    }
    html(StatusCode::OK, auth_page(&state, views::pages::AuthKind::SignUp, "", None))
}

async fn sign_in_page(State(state): State<SharedState>, MaybeUser(user): MaybeUser) -> Response {
    if user.is_some() {
        return Redirect::to("/dashboard").into_response();
    }
    html(StatusCode::OK, auth_page(&state, views::pages::AuthKind::SignIn, "", None))
}

async fn sign_up(State(state): State<SharedState>, Form(form): Form<Credentials>) -> Result<Response, AppError> {
    let Some(client) = &state.email else {
        return Ok(html(
            StatusCode::SERVICE_UNAVAILABLE,
            auth_page(
                &state,
                views::pages::AuthKind::SignUp,
                &form.email,
                Some("Email delivery is temporarily unavailable. Please try again later."),
            ),
        ));
    };
    match crate::verification::start(&state.pool, client, &form.email, form.password).await {
        Ok(crate::verification::Start::Pending { token, delivered }) => {
            let mut response = if delivered {
                Redirect::to("/verify-email").into_response()
            } else {
                verification_page(
                    &state,
                    StatusCode::SERVICE_UNAVAILABLE,
                    60,
                    Some("We couldn’t send your code. Wait a minute, then try resending."),
                )
            };
            response
                .headers_mut()
                .insert(header::SET_COOKIE, crate::verification::cookie(&token, state.cfg.secure_cookies()));
            Ok(response)
        }
        Ok(crate::verification::Start::Limited) => Ok(html(
            StatusCode::TOO_MANY_REQUESTS,
            auth_page(
                &state,
                views::pages::AuthKind::SignUp,
                &form.email,
                Some("Please wait at least a minute before trying again. Too many attempts? Try again in an hour."),
            ),
        )),
        Err(users::SignUpError::Other(e)) => Err(e.into()),
        Err(e) => Ok(html(
            StatusCode::UNPROCESSABLE_ENTITY,
            auth_page(&state, views::pages::AuthKind::SignUp, &form.email, Some(&e.to_string())),
        )),
    }
}

fn verification_page(state: &SharedState, status: StatusCode, seconds: i64, error: Option<&str>) -> Response {
    let body = maud::html! {
        section class="page narrow verification" {
            h1 { "Check your email" }
            p { "If this email can be registered, we sent a six-character code. Enter it below to finish creating your account. Already registered? " a href="/sign-in" { "Sign in" } "." }
            p { "The code expires in 10 minutes. Check your spam folder too." }
            @if let Some(error) = error { p role="alert" class="alert" { (error) } }
            form class="form" method="post" action="/verify-email" {
                label for="code" { "Verification code" }
                input id="code" name="code" type="text" required maxlength="6" minlength="6" autocomplete="one-time-code" autocapitalize="characters" spellcheck="false" autofocus;
                button class="btn btn-primary" type="submit" { "Verify email" }
            }
            form class="form" method="post" action="/verify-email/resend" {
                button class="btn" type="submit" data-resend-seconds=(seconds) disabled[seconds > 0] { "Resend code" }
                p data-resend-status aria-live="polite" { @if seconds > 0 { "You can resend in " (seconds) " seconds. Reload this page after the wait if JavaScript is disabled." } }
            }
            p { "Wrong email or a different browser? " a href="/sign-up" { "Start again" } }
        }
        script defer src=(state.asset_url("verification.js")) {}
    };
    let mut response = html(
        status,
        views::layout(state, Page { title: "Verify your email", path: "/verify-email", user: None, body }),
    );
    response.headers_mut().insert("x-robots-tag", axum::http::HeaderValue::from_static("noindex, nofollow"));
    response
}
async fn verify_email_page(State(state): State<SharedState>, headers: HeaderMap) -> Result<Response, AppError> {
    let Some(token) = crate::verification::token(&headers) else {
        return Ok(Redirect::to("/sign-up").into_response());
    };
    let seconds = crate::verification::remaining(&state.pool, token).await?;
    Ok(verification_page(&state, StatusCode::OK, seconds, None))
}
#[derive(Deserialize)]
struct VerificationForm {
    code: String,
}
async fn verify_email(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Form(form): Form<VerificationForm>,
) -> Result<Response, AppError> {
    let Some(token) = crate::verification::token(&headers) else {
        return Ok(Redirect::to("/sign-up").into_response());
    };
    let Some(client) = &state.email else {
        return Ok(verification_page(
            &state,
            StatusCode::SERVICE_UNAVAILABLE,
            0,
            Some("Email verification is temporarily unavailable."),
        ));
    };
    if let Some(user) = crate::verification::verify(&state.pool, client, token, &form.code).await? {
        let mut response = start_session(&state, &user).await?;
        response.headers_mut().append(header::SET_COOKIE, crate::verification::cookie("", state.cfg.secure_cookies()));
        #[cfg(feature = "posthog")]
        crate::analytics::record_user(&user);
        #[cfg(feature = "posthog-product")]
        state.track(&user, "user signed up", serde_json::json!({"method":"email", "email_verified":true}));
        return Ok(response);
    }
    let seconds = crate::verification::remaining(&state.pool, token).await?;
    Ok(verification_page(
        &state,
        StatusCode::UNPROCESSABLE_ENTITY,
        seconds,
        Some("This code is incorrect, expired, or has reached its attempt limit. Request a new code."),
    ))
}
async fn resend_verification(State(state): State<SharedState>, headers: HeaderMap) -> Result<Response, AppError> {
    let Some(token) = crate::verification::token(&headers) else {
        return Ok(Redirect::to("/sign-up").into_response());
    };
    let Some(client) = &state.email else {
        return Ok(verification_page(
            &state,
            StatusCode::SERVICE_UNAVAILABLE,
            0,
            Some("Email delivery is temporarily unavailable."),
        ));
    };
    let (status, message) = match crate::verification::resend(&state.pool, client, token).await? {
        crate::verification::Start::Pending { delivered: true, .. } => {
            (StatusCode::OK, "A new code has been sent. Only the newest code will work.")
        }
        crate::verification::Start::Pending { delivered: false, .. } => {
            (StatusCode::SERVICE_UNAVAILABLE, "We couldn’t send your code. Wait a minute, then try again.")
        }
        crate::verification::Start::Limited => (
            StatusCode::TOO_MANY_REQUESTS,
            "Please wait at least a minute between requests. Too many attempts? Try again in an hour, or start again if your signup expired.",
        ),
    };
    let seconds = crate::verification::remaining(&state.pool, token).await?;
    Ok(verification_page(&state, status, seconds, Some(message)))
}

/// Auth forms require positive same-origin evidence, including clients without Fetch Metadata.
async fn auth_origin(
    State(state): State<SharedState>,
    request: axum::extract::Request,
    next: middleware::Next,
) -> Response {
    if request.method() == axum::http::Method::POST
        && matches!(
            request.uri().path(),
            "/sign-up"
                | "/verify-email"
                | "/verify-email/resend"
                | "/passkeys/register/options"
                | "/passkeys/register"
                | "/passkeys/sign-in/options"
                | "/passkeys/sign-in"
                | crate::two_factor::SIGN_IN_PATH
                | crate::two_factor::SETTINGS_PATH
        )
        && request.headers().get(header::ORIGIN).and_then(|v| v.to_str().ok())
            != Some(state.cfg.site_url.trim_end_matches('/'))
    {
        return StatusCode::FORBIDDEN.into_response();
    }
    next.run(request).await
}

async fn sign_in(State(state): State<SharedState>, Form(form): Form<Credentials>) -> Result<Response, AppError> {
    match users::verify_credentials(&state.pool, &form.email, form.password).await? {
        Some(user) => {
            #[cfg(feature = "posthog")]
            crate::analytics::record_user(&user);
            // With a second factor the password alone earns a challenge, not a session.
            if app_auth::two_factor::is_enabled(&state.pool, user.id).await? {
                return crate::two_factor::start_challenge(&state, &user).await;
            }
            let response = start_session(&state, &user).await?;
            #[cfg(feature = "posthog-product")]
            state.track(&user, "user signed in", serde_json::json!({}));
            Ok(response)
        }
        None => Ok(html(
            StatusCode::UNPROCESSABLE_ENTITY,
            auth_page(&state, views::pages::AuthKind::SignIn, &form.email, Some("Wrong email or password.")),
        )),
    }
}

/// A new session for `user`, as the cookie to set. Every sign-in method ends here.
pub(crate) async fn session_cookie(
    state: &SharedState,
    user: &users::User,
) -> Result<axum::http::HeaderValue, AppError> {
    let ttl = TimeDuration::days(state.cfg.session_ttl_days);
    let token = sessions::create(&state.pool, user.id, ttl).await?;
    Ok(sessions::session_cookie(&token, ttl, state.cfg.secure_cookies()))
}

pub(crate) async fn start_session(state: &SharedState, user: &users::User) -> Result<Response, AppError> {
    let cookie = session_cookie(state, user).await?;
    Ok(([(header::SET_COOKIE, cookie)], Redirect::to("/dashboard")).into_response())
}

async fn sign_out(
    State(state): State<SharedState>,
    MaybeUser(user): MaybeUser,
    headers: HeaderMap,
) -> Result<Response, AppError> {
    #[cfg(feature = "posthog")]
    if let Some(user) = &user {
        crate::analytics::record_user(user);
    }
    if let Some(token) = sessions::token_from_headers(&headers) {
        sessions::delete(&state.pool, token).await?;
    }
    #[cfg(feature = "posthog-product")]
    if let Some(user) = &user {
        state.track(user, "user signed out", serde_json::json!({}));
    }
    let _ = user;
    let cookie = sessions::clear_cookie(state.cfg.secure_cookies());
    Ok(([(header::SET_COOKIE, cookie)], Redirect::to("/")).into_response())
}

#[cfg(feature = "docs")]
async fn docs_index(State(state): State<SharedState>, MaybeUser(user): MaybeUser) -> Result<Response, AppError> {
    let doc = &state.docs.welcome;
    let page =
        Page { title: &doc.title, path: &doc.path, user: user.as_ref(), body: views::docs::page(&state.docs, doc) };
    Ok(html(StatusCode::OK, views::layout_with_metadata(&state, page, Some(&doc.description), None)))
}

#[cfg(feature = "docs")]
async fn docs_article(
    State(state): State<SharedState>,
    MaybeUser(user): MaybeUser,
    axum::extract::Path(slug): axum::extract::Path<String>,
    headers: HeaderMap,
) -> Result<Response, AppError> {
    if slug == "welcome" {
        return Ok(Redirect::permanent("/docs").into_response());
    }
    let Some(doc) = state.docs.pages.iter().find(|doc| doc.slug == slug) else {
        return Ok(errors::not_found(&headers, || {
            let page = Page { title: "Not found", path: "", user: user.as_ref(), body: views::pages::not_found() };
            html(StatusCode::NOT_FOUND, views::layout(&state, page))
        }));
    };
    let page =
        Page { title: &doc.title, path: &doc.path, user: user.as_ref(), body: views::docs::page(&state.docs, doc) };
    Ok(html(StatusCode::OK, views::layout_with_metadata(&state, page, Some(&doc.description), None)))
}

#[cfg(feature = "stripe")]
fn stripe_client(state: &SharedState) -> Result<&crate::billing::StripeClient, AppError> {
    state
        .stripe
        .as_ref()
        .ok_or_else(|| AppError::Status(StatusCode::SERVICE_UNAVAILABLE, "Billing is not configured yet.".into()))
}
#[cfg(feature = "stripe")]
async fn billing_response(
    state: &SharedState,
    user: &users::User,
    status: StatusCode,
    message: Option<&str>,
) -> Result<Response, AppError> {
    let billing = crate::billing::status(&state.pool, user.id).await?;
    let body = views::pages::billing(&billing, state.stripe.as_ref().map(|s| &s.cfg), message);
    Ok(html(status, views::layout(state, Page { title: "Billing", path: "/billing", user: Some(user), body })))
}
#[cfg(feature = "stripe")]
async fn billing_page(State(state): State<SharedState>, CurrentUser(user): CurrentUser) -> Result<Response, AppError> {
    billing_response(&state, &user, StatusCode::OK, None).await
}
#[cfg(feature = "stripe")]
async fn billing_success(
    State(state): State<SharedState>,
    CurrentUser(user): CurrentUser,
) -> Result<Response, AppError> {
    billing_response(&state, &user, StatusCode::OK, Some("Thanks! Your billing status updates after Stripe confirms your checkout. If it is still pending, refresh this page shortly.")).await
}
#[cfg(feature = "stripe")]
#[derive(Deserialize)]
struct BillingForm {
    #[serde(default)]
    mode: String,
}
#[cfg(feature = "stripe")]
async fn start_checkout(
    State(state): State<SharedState>,
    CurrentUser(user): CurrentUser,
    Form(form): Form<BillingForm>,
) -> Result<Response, AppError> {
    use crate::billing::Checkout;
    if user.is_admin {
        return billing_response(&state, &user, StatusCode::OK, None).await;
    }
    let stripe = stripe_client(&state)?;
    let available = match form.mode.as_str() {
        "subscription" => stripe.cfg.subscriptions_enabled(),
        "payment" => stripe.cfg.payments_enabled(),
        _ => false,
    };
    if !available {
        return billing_response(
            &state,
            &user,
            StatusCode::UNPROCESSABLE_ENTITY,
            Some("Choose an available billing plan."),
        )
        .await;
    }
    let message = match crate::billing::checkout(&state.pool, stripe, &user, &form.mode, &state.cfg.site_url).await {
        Ok(Checkout::Redirect(url)) => return Ok(Redirect::to(&url).into_response()),
        Ok(Checkout::Pending) => "Your payment is pending. Please wait for confirmation.",
        Ok(Checkout::Retry) => "Your previous checkout has ended. Choose a plan to try again.",
        Ok(Checkout::AdminAccess) => "Your admin role includes all paid features. No payment is required.",
        Ok(Checkout::AlreadyPurchased) => "You already have a purchase or subscription. Manage it below.",
        Err(error) => {
            tracing::error!(%error, "checkout failed");
            return billing_response(
                &state,
                &user,
                StatusCode::BAD_GATEWAY,
                Some("Unable to start checkout. Please try again shortly."),
            )
            .await;
        }
    };
    billing_response(&state, &user, StatusCode::OK, Some(message)).await
}
#[cfg(feature = "stripe")]
async fn billing_portal(
    State(state): State<SharedState>,
    CurrentUser(user): CurrentUser,
) -> Result<Response, AppError> {
    let url = stripe_client(&state)?.portal(&state.pool, user.id, &state.cfg.site_url).await?;
    Ok(Redirect::to(&url).into_response())
}
#[cfg(feature = "stripe")]
async fn stripe_webhook(
    State(state): State<SharedState>,
    headers: HeaderMap,
    body: axum::body::Bytes,
) -> Result<StatusCode, AppError> {
    let stripe = stripe_client(&state)?;
    let signature = headers.get("stripe-signature").and_then(|v| v.to_str().ok()).unwrap_or_default();
    crate::billing::webhook(&state.pool, stripe, signature, &body).await?;
    Ok(StatusCode::OK)
}
