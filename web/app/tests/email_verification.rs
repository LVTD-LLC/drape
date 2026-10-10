use drape as app;

use app_core::Config;
use axum::{
    body::Body,
    http::{Request, StatusCode, header},
};
use tower::ServiceExt;

#[sqlx::test(migrations = "../migrations")]
async fn signup_never_authenticates_without_email_delivery(pool: sqlx::PgPool) {
    let cfg = Config {
        bind_addr: "127.0.0.1:0".into(),
        site_url: "http://test.local".into(),
        database_url: String::new(),
        session_ttl_days: 30,
    };
    let app = app::build(cfg, pool.clone()).1;
    let response = app
        .oneshot(
            Request::post("/sign-up")
                .header(header::ORIGIN, "http://test.local")
                .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
                .body(Body::from("email=new%40example.com&password=correct-horse"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert!(!response.headers().contains_key(header::SET_COOKIE));
    assert_eq!(sqlx::query!("SELECT count(*) AS count FROM users").fetch_one(&pool).await.unwrap().count, Some(0));
}

mod common;
use http_body_util::BodyExt;
fn app(pool: sqlx::PgPool) -> (app::SharedState, axum::Router) {
    common::mail_app(app::build(
        Config {
            bind_addr: "127.0.0.1:0".into(),
            site_url: "http://test.local".into(),
            database_url: String::new(),
            session_ttl_days: 30,
        },
        pool,
    ))
}
async fn post(app: &axum::Router, path: &str, body: &str, cookie: &str) -> axum::response::Response {
    app.clone()
        .oneshot(
            Request::post(path)
                .header(header::ORIGIN, "http://test.local")
                .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
                .header(header::COOKIE, cookie)
                .body(Body::from(body.to_owned()))
                .unwrap(),
        )
        .await
        .unwrap()
}
fn cookie(response: &axum::response::Response) -> String {
    response.headers()[header::SET_COOKIE].to_str().unwrap().split(';').next().unwrap().into()
}
async fn signup(app: &axum::Router, email: &str) -> String {
    let r = post(app, "/sign-up", &format!("email={email}&password=correct-horse"), "").await;
    assert_eq!(r.status(), StatusCode::SEE_OTHER);
    assert_eq!(r.headers()[header::LOCATION], "/verify-email");
    let c = cookie(&r);
    assert!(c.starts_with("signup="));
    c
}
#[sqlx::test(migrations = "../migrations")]
async fn pending_cannot_sign_in_then_code_is_single_use_and_browser_bound(pool: sqlx::PgPool) {
    let (_, app) = app(pool.clone());
    let c = signup(&app, "flow@example.com").await;
    assert_eq!(sqlx::query!("SELECT count(*) AS count FROM users").fetch_one(&pool).await.unwrap().count, Some(0));
    assert_eq!(
        post(&app, "/sign-in", "email=flow@example.com&password=correct-horse", "").await.status(),
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let dashboard = app
        .clone()
        .oneshot(Request::get("/dashboard").header(header::COOKIE, &c).body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(dashboard.headers()[header::LOCATION], "/sign-in");
    let code = common::code("flow@example.com");
    assert_eq!(code.len(), 6);
    assert_eq!(
        post(&app, "/verify-email", &format!("code={code}"), &format!("signup={}", "a".repeat(64))).await.status(),
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let verified = common::complete(&app, &c, "flow@example.com").await;
    assert_eq!(verified.status(), StatusCode::SEE_OTHER);
    assert!(cookie(&verified).starts_with("session="));
    assert_eq!(common::complete(&app, &c, "flow@example.com").await.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        sqlx::query!("SELECT count(*) AS count FROM pending_signups").fetch_one(&pool).await.unwrap().count,
        Some(0)
    );
}
#[sqlx::test(migrations = "../migrations")]
async fn cooldown_rotation_expiry_and_attempt_limit(pool: sqlx::PgPool) {
    let (_, app) = app(pool.clone());
    let c = signup(&app, "rotation@example.com").await;
    let old = common::code("rotation@example.com");
    assert_eq!(post(&app, "/verify-email/resend", "", &c).await.status(), StatusCode::TOO_MANY_REQUESTS);
    sqlx::query!("UPDATE pending_signups SET last_sent_at = now() - interval '61 seconds'")
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(post(&app, "/verify-email/resend", "", &c).await.status(), StatusCode::OK);
    let new = common::code("rotation@example.com");
    assert_ne!(old, new);
    assert_eq!(
        post(&app, "/verify-email", &format!("code={old}"), &c).await.status(),
        StatusCode::UNPROCESSABLE_ENTITY
    );
    for _ in 0..4 {
        assert_eq!(post(&app, "/verify-email", "code=!!!!!!", &c).await.status(), StatusCode::UNPROCESSABLE_ENTITY);
    }
    assert_eq!(common::complete(&app, &c, "rotation@example.com").await.status(), StatusCode::UNPROCESSABLE_ENTITY);
    sqlx::query!("UPDATE pending_signups SET attempts = 0, expires_at = now() - interval '1 second'")
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(common::complete(&app, &c, "rotation@example.com").await.status(), StatusCode::UNPROCESSABLE_ENTITY);
}
#[sqlx::test(migrations = "../migrations")]
async fn concurrent_consumption_has_one_winner_and_csrf_is_required(pool: sqlx::PgPool) {
    let (_, app) = app(pool.clone());
    let c = signup(&app, "race@example.com").await;
    let code = common::code("race@example.com");
    for origin in [None, Some("https://evil.example")] {
        let mut request = Request::post("/verify-email")
            .header(header::COOKIE, &c)
            .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded");
        if let Some(origin) = origin {
            request = request.header(header::ORIGIN, origin);
        }
        let r = app.clone().oneshot(request.body(Body::from(format!("code={code}"))).unwrap()).await.unwrap();
        assert_eq!(r.status(), StatusCode::FORBIDDEN);
    }
    let (a, b) =
        tokio::join!(common::complete(&app, &c, "race@example.com"), common::complete(&app, &c, "race@example.com"));
    assert_eq!([a.status(), b.status()].iter().filter(|&&s| s == StatusCode::SEE_OTHER).count(), 1);
    assert_eq!(sqlx::query!("SELECT count(*) AS count FROM sessions").fetch_one(&pool).await.unwrap().count, Some(1));
}
#[sqlx::test(migrations = "../migrations")]
async fn replacement_signup_cannot_use_an_older_browser_or_password(pool: sqlx::PgPool) {
    let (_, app) = app(pool.clone());
    let old_cookie = signup(&app, "replacement@example.com").await;
    let old_code = common::code("replacement@example.com");
    sqlx::query!("UPDATE pending_signups SET last_sent_at = now() - interval '61 seconds'")
        .execute(&pool)
        .await
        .unwrap();
    let new_cookie =
        cookie(&post(&app, "/sign-up", "email=replacement@example.com&password=new-correct-horse", "").await);
    assert_ne!(old_cookie, new_cookie);
    assert_eq!(
        post(&app, "/verify-email", &format!("code={old_code}"), &old_cookie).await.status(),
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(common::complete(&app, &new_cookie, "replacement@example.com").await.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        post(&app, "/sign-in", "email=replacement@example.com&password=correct-horse", "").await.status(),
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        post(&app, "/sign-in", "email=replacement@example.com&password=new-correct-horse", "").await.status(),
        StatusCode::SEE_OTHER
    );
}
#[sqlx::test(migrations = "../migrations")]
async fn existing_account_is_not_modified_and_email_budget_persists(pool: sqlx::PgPool) {
    let (_, app) = app(pool.clone());
    app_auth::users::sign_up(&pool, "existing@example.com", "original-password".into()).await.unwrap();
    let c = signup(&app, "existing@example.com").await;
    assert_eq!(post(&app, "/verify-email", "code=123456", &c).await.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert!(
        app_auth::users::verify_credentials(&pool, "existing@example.com", "original-password".into())
            .await
            .unwrap()
            .is_some()
    );
    for _ in 0..4 {
        signup(&app, "existing@example.com").await;
    }
    let (state2, app2) = self::app(pool);
    assert_eq!(
        post(&app2, "/sign-up", "email=existing@example.com&password=correct-horse", "").await.status(),
        StatusCode::TOO_MANY_REQUESTS
    );
    drop(state2);
}
#[sqlx::test(migrations = "../migrations")]
async fn provider_failure_does_not_create_account_and_allows_later_retry(pool: sqlx::PgPool) {
    let (state, router) = app(pool.clone());
    drop(router);
    let mut state = state;
    std::sync::Arc::get_mut(&mut state).unwrap().email = Some(
        app::verification::Client::with_endpoint(
            app::verification::Config {
                api_key: "test".into(),
                domain: "mg.example.com".into(),
                from: "noreply@example.com".into(),
                hash_key: "test-only-long-key-not-production-12345".into(),
            },
            "http://127.0.0.1:1/messages".into(),
        )
        .unwrap(),
    );
    let app = app::routes::router(state);
    let r = post(&app, "/sign-up", "email=failure@example.com&password=correct-horse", "").await;
    assert_eq!(r.status(), StatusCode::SERVICE_UNAVAILABLE);
    let c = cookie(&r);
    let body = r.into_body().collect().await.unwrap().to_bytes();
    assert!(String::from_utf8_lossy(&body).contains("couldn’t send"));
    assert_eq!(sqlx::query!("SELECT count(*) AS count FROM users").fetch_one(&pool).await.unwrap().count, Some(0));
    assert!(!sqlx::query!("SELECT delivered FROM pending_signups").fetch_one(&pool).await.unwrap().delivered);
    let (_, working) = self::app(pool.clone());
    sqlx::query!("UPDATE pending_signups SET last_sent_at = now() - interval '61 seconds'")
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(post(&working, "/verify-email/resend", "", &c).await.status(), StatusCode::OK);
    assert_eq!(common::complete(&working, &c, "failure@example.com").await.status(), StatusCode::SEE_OTHER);
}

#[sqlx::test(migrations = "../migrations")]
async fn recipient_injection_is_rejected_before_delivery(pool: sqlx::PgPool) {
    let (_, app) = app(pool.clone());
    for email in [
        "victim%40example.com%0D%0ABcc%3Ax",
        "Name%3Cvictim%40example.com%3E",
        "one%40example.com,two%40example.com",
        "a%40example..com",
    ] {
        assert_eq!(
            post(&app, "/sign-up", &format!("email={email}&password=correct-horse"), "").await.status(),
            StatusCode::UNPROCESSABLE_ENTITY
        );
    }
    assert_eq!(
        sqlx::query!("SELECT count(*) AS count FROM pending_signups").fetch_one(&pool).await.unwrap().count,
        Some(0)
    );
}

#[sqlx::test(migrations = "../migrations")]
async fn all_signup_posts_require_origin_and_cookies_are_secure_on_https(pool: sqlx::PgPool) {
    let (_, app) = common::mail_app(app::build(
        Config {
            bind_addr: "127.0.0.1:0".into(),
            site_url: "https://test.local".into(),
            database_url: String::new(),
            session_ttl_days: 30,
        },
        pool.clone(),
    ));
    for path in ["/sign-up", "/verify-email", "/verify-email/resend"] {
        for origin in [None, Some("https://evil.example")] {
            let mut request = Request::post(path).header(header::CONTENT_TYPE, "application/x-www-form-urlencoded");
            if let Some(origin) = origin {
                request = request.header(header::ORIGIN, origin);
            }
            let response = app.clone().oneshot(request.body(Body::empty()).unwrap()).await.unwrap();
            assert_eq!(response.status(), StatusCode::FORBIDDEN, "{path}");
        }
    }
    let response = app
        .clone()
        .oneshot(
            Request::post("/sign-up")
                .header(header::ORIGIN, "https://test.local")
                .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
                .body(Body::from("email=secure%40example.com&password=correct-horse"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    let pending_cookie = cookie(&response);
    let header = response.headers()[header::SET_COOKIE].to_str().unwrap();
    for attribute in ["HttpOnly", "SameSite=Strict", "Secure"] {
        assert!(header.contains(attribute));
    }
    let response = app
        .oneshot(
            Request::post("/verify-email")
                .header(header::ORIGIN, "https://test.local")
                .header(header::CONTENT_TYPE, "application/x-www-form-urlencoded")
                .header(header::COOKIE, pending_cookie)
                .body(Body::from(format!("code={}", common::code("secure@example.com").to_ascii_lowercase())))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    let cookies: Vec<_> = response.headers().get_all(header::SET_COOKIE).iter().map(|c| c.to_str().unwrap()).collect();
    assert!(cookies.iter().any(|c| c.starts_with("session=") && c.contains("Secure") && c.contains("HttpOnly")));
    assert!(cookies.iter().any(|c| c.starts_with("signup=;") && c.contains("Max-Age=0")));
}
