//! The app shell: state, router, pages. This is the crate you edit to build
//! your product; the `drape-*` crates underneath are upgraded in place.
//!
//! - [`routes`] axum handlers
//! - [`views`]  maud templates
//! - [`assets`] embedded static files
//! - [`api`]    optional JSON API at `/api/v1`, authenticated with [`api_keys`]
//! - [`mcp`]    optional MCP server at `/mcp` for coding agents, same keys
//! - [`jobs`]   background job kinds and their registry
//! - [`avatars`] optional profile pictures: the example of file storage (`app_core::storage`)
//! - [`two_factor`] authenticator-app enrolment and the sign-in code prompt

#[cfg(feature = "posthog")]
pub mod analytics;
#[cfg(any(feature = "posthog", feature = "sentry-server"))]
pub mod observability;
#[cfg(feature = "sentry")]
pub mod sentry;
pub use errors::AppError;
pub mod admin;
pub mod ai;
#[cfg(feature = "api")]
pub mod api;
#[cfg(feature = "api")]
pub mod api_keys;
pub mod assets;
#[cfg(feature = "storage")]
pub mod avatars;
#[cfg(feature = "stripe")]
pub mod billing;
#[cfg(feature = "blog")]
pub mod blog;
#[cfg(feature = "docs")]
pub mod docs;
mod errors;
pub mod jobs;
#[cfg(feature = "mcp")]
pub mod mcp;
pub mod passkeys;
pub mod routes;
pub mod settings;
pub mod two_factor;
pub mod verification;
pub mod views;

use app_auth::{AuthState, RelyingParty};
use app_core::{Config, Pool};
use rust_embed::Embed;
use sha2::{Digest, Sha256};
use std::sync::Arc;

#[derive(Embed)]
#[folder = "assets/"]
pub struct Assets;

/// This app's schema: `migrations/` at the workspace root, embedded and
/// applied on connect (`app_core::db::connect`).
pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("../migrations");

pub struct AppState {
    pub ai: Option<Arc<ai::Gateway>>,
    pub cfg: Config,
    #[cfg(feature = "posthog")]
    pub analytics: Option<analytics::Config>,
    #[cfg(feature = "sentry")]
    pub sentry: Option<sentry::Config>,
    #[cfg(feature = "stripe")]
    pub stripe: Option<billing::StripeClient>,
    pub email: Option<verification::Client>,
    /// Where uploads go: an S3-compatible bucket or a local directory.
    #[cfg(feature = "storage")]
    pub storage: app_core::storage::Storage,
    /// WebAuthn relying party (passkeys), derived from `SITE_URL` once.
    pub rp: RelyingParty,
    pub pool: Pool,
    /// Short hash of all embedded assets, used to cache-bust asset URLs.
    pub asset_version: String,
    /// Public sitemap, rendered once at startup and shared across requests.
    pub sitemap: axum::body::Bytes,
    #[cfg(feature = "docs")]
    pub docs: docs::Docs,
    #[cfg(feature = "blog")]
    pub blog: blog::Blog,
}

impl AppState {
    pub fn asset_url(&self, name: &str) -> String {
        format!("/assets/{name}?v={}", self.asset_version)
    }
}

pub type SharedState = Arc<AppState>;

impl AuthState for AppState {
    fn pool(&self) -> &Pool {
        &self.pool
    }
}

/// Build state and router from a config and an already-migrated pool.
/// Used by `main` and by the integration tests.
pub fn build(cfg: Config, pool: Pool) -> (SharedState, axum::Router) {
    build_configured(
        cfg,
        pool,
        #[cfg(feature = "posthog")]
        None,
        #[cfg(feature = "sentry")]
        None,
        #[cfg(feature = "stripe")]
        None,
        #[cfg(feature = "storage")]
        scratch_storage(),
    )
}

/// Uploads under the system temp directory: what tests and [`build`] use.
/// `main` reads `STORAGE_*` from the environment instead.
#[cfg(feature = "storage")]
pub fn scratch_storage() -> app_core::storage::Storage {
    app_core::storage::Storage::local(std::env::temp_dir().join(concat!(env!("CARGO_PKG_NAME"), "-uploads")))
        .expect("the system temp directory is writable")
}

#[cfg(feature = "posthog")]
pub fn build_with_analytics(
    cfg: Config,
    pool: Pool,
    analytics: Option<analytics::Config>,
) -> (SharedState, axum::Router) {
    build_configured(
        cfg,
        pool,
        analytics,
        #[cfg(feature = "sentry")]
        None,
        #[cfg(feature = "stripe")]
        None,
        #[cfg(feature = "storage")]
        scratch_storage(),
    )
}

pub fn build_configured(
    cfg: Config,
    pool: Pool,
    #[cfg(feature = "posthog")] analytics: Option<analytics::Config>,
    #[cfg(feature = "sentry")] sentry: Option<sentry::Config>,
    #[cfg(feature = "stripe")] stripe: Option<billing::StripeClient>,
    #[cfg(feature = "storage")] storage: app_core::storage::Storage,
) -> (SharedState, axum::Router) {
    let asset_version = {
        let mut h = Sha256::new();
        for name in Assets::iter() {
            h.update(name.as_bytes());
            if let Some(f) = Assets::get(&name) {
                h.update(&f.data);
            }
        }
        h.finalize()[..6].iter().map(|b| format!("{b:02x}")).collect()
    };
    #[cfg(feature = "blog")]
    let blog = blog::Blog::load(&cfg.site_url).expect("blog content must be valid before serving");
    #[cfg(feature = "blog")]
    let blog_urls = maud::html! {
        url { loc { (cfg.site_url.trim_end_matches('/')) "/blog" } }
        @for post in &blog.posts {
            url { loc { (cfg.site_url.trim_end_matches('/')) (post.path) } }
        }
    };
    #[cfg(not(feature = "blog"))]
    let blog_urls = maud::html! {};
    #[cfg(feature = "docs")]
    let docs = docs::Docs::load().expect("docs content must be valid before serving");
    #[cfg(feature = "docs")]
    let docs_urls = maud::html! {
        url { loc { (cfg.site_url.trim_end_matches('/')) "/docs" } }
        @for doc in &docs.pages { url { loc { (cfg.site_url.trim_end_matches('/')) (doc.path) } } }
    };
    #[cfg(not(feature = "docs"))]
    let docs_urls = maud::html! {};
    let sitemap = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>{}",
        maud::html! {
            urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" {
                (docs_urls)
                url { loc { (cfg.site_url.trim_end_matches('/')) "/" } }
                (blog_urls)
            }
        }
        .into_string()
    )
    .into();
    let rp = RelyingParty::from_site_url(&cfg.site_url, views::SITE_NAME)
        .expect("SITE_URL must be an http(s) origin so passkeys can be bound to it");
    let state = Arc::new(AppState {
        ai: None,
        cfg,
        #[cfg(feature = "posthog")]
        analytics,
        #[cfg(feature = "sentry")]
        sentry,
        #[cfg(feature = "stripe")]
        stripe,
        pool,
        email: None,
        #[cfg(feature = "storage")]
        storage,
        rp,
        asset_version,
        sitemap,
        #[cfg(feature = "docs")]
        docs,
        #[cfg(feature = "blog")]
        blog,
    });
    let router = routes::router(state.clone());
    (state, router)
}

/// The router a worker-only process serves (`JOBS_WORKER=only` or the
/// `worker` command): just the health check the container expects.
pub fn worker_router() -> axum::Router {
    axum::Router::new()
        .route("/healthz", axum::routing::get(|| async { "ok" }))
        .layer(axum::middleware::from_fn(app_core::http::security_headers))
}

/// Only public, published pages; feature-disabled and draft content never enters this list.
pub fn indexnow_paths(state: &SharedState) -> Vec<String> {
    let mut paths = vec!["/".to_string()];
    #[cfg(feature = "blog")]
    {
        paths.push("/blog".into());
        paths.extend(state.blog.posts.iter().map(|post| post.path.clone()));
    }
    #[cfg(feature = "docs")]
    {
        paths.push("/docs".into());
        paths.extend(state.docs.pages.iter().map(|doc| doc.path.clone()));
    }
    let _ = state; // Both optional content modules can be disabled.
    paths.sort();
    paths.dedup();
    paths
}
