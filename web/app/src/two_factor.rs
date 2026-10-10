//! Two-factor authentication: enrolment on `/settings/two-factor` and the
//! code prompt on `/sign-in/two-factor`. The secrets, recovery codes and
//! sign-in challenges are `app_auth::two_factor`; this module renders
//! pages and decides which password checks guard each action.
//!
//! Enabling, disabling and regenerating recovery codes all require the
//! current password, like adding a passkey. Confirming the enrolment code
//! does not: the pending secret was already password-gated and the code
//! itself proves the app was set up.

use crate::{AppError, SharedState, routes, views};
use app_auth::two_factor::{self, ChallengeError, Setup, Status, TwoFactorError};
use app_auth::{CurrentUser, MaybeUser, User, password, users};
use axum::extract::{Form, Query, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::{IntoResponse, Redirect, Response};
use serde::Deserialize;
use time::OffsetDateTime;

pub const SETTINGS_PATH: &str = "/settings/two-factor";
pub const SIGN_IN_PATH: &str = "/sign-in/two-factor";

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum SettingsForm {
    Begin {
        #[serde(default)]
        password: String,
    },
    Confirm {
        #[serde(default)]
        code: String,
    },
    Cancel,
    RecoveryCodes {
        #[serde(default)]
        password: String,
    },
    Disable {
        #[serde(default)]
        password: String,
    },
}

#[derive(Default, Deserialize)]
pub struct Notice {
    saved: Option<String>,
}

impl Notice {
    fn message(&self) -> Option<&'static str> {
        match self.saved.as_deref() {
            Some("off") => Some("Two-factor authentication is off. Your password alone signs you in."),
            Some("cancelled") => Some("Setup cancelled. Nothing was changed."),
            _ => None,
        }
    }
}

/// Messages and one-time content for one rendering of the settings page.
#[derive(Default)]
struct Flash<'a> {
    error: Option<&'a str>,
    notice: Option<&'a str>,
    recovery_codes: Option<&'a [String]>,
}

async fn render(
    state: &SharedState,
    user: &User,
    status_code: StatusCode,
    flash: Flash<'_>,
) -> Result<Response, AppError> {
    let status = two_factor::status(&state.pool, user.id).await?;
    let setup = match status {
        Status::Pending => two_factor::pending(&state.pool, user.id, views::SITE_NAME, &user.email).await?,
        _ => None,
    };
    let view = views::two_factor::View {
        status: &status,
        setup: setup.as_ref(),
        recovery_codes: flash.recovery_codes,
        error: flash.error,
        notice: flash.notice,
    };
    let page = views::Page {
        title: "Two-factor authentication",
        path: SETTINGS_PATH,
        user: Some(user),
        body: views::two_factor::page(&view),
    };
    Ok(routes::html(status_code, views::layout(state, page)))
}

pub async fn settings_page(
    State(state): State<SharedState>,
    CurrentUser(user): CurrentUser,
    Query(notice): Query<Notice>,
) -> Result<Response, AppError> {
    render(&state, &user, StatusCode::OK, Flash { notice: notice.message(), ..Flash::default() }).await
}

/// Whether `supplied` is the signed-in user's current password.
async fn password_ok(state: &SharedState, user: &User, supplied: String) -> Result<bool, AppError> {
    Ok(supplied.len() <= password::MAX_LEN
        && users::verify_credentials(&state.pool, &user.email, supplied).await?.is_some())
}

pub async fn settings_submit(
    State(state): State<SharedState>,
    CurrentUser(user): CurrentUser,
    Form(form): Form<SettingsForm>,
) -> Result<Response, AppError> {
    let error = match form {
        SettingsForm::Begin { password } => {
            if !password_ok(&state, &user, password).await? {
                "Enter your current password to turn on two-factor authentication."
            } else {
                match two_factor::begin(&state.pool, user.id, views::SITE_NAME, &user.email).await {
                    Ok(Setup { .. }) => return Ok(Redirect::to(SETTINGS_PATH).into_response()),
                    Err(TwoFactorError::Other(error)) => return Err(error.into()),
                    Err(error) => return failed(&state, &user, error).await,
                }
            }
        }
        SettingsForm::Confirm { code } => {
            match two_factor::confirm(&state.pool, user.id, &code, OffsetDateTime::now_utc()).await {
                Ok(codes) => {
                    #[cfg(feature = "posthog-product")]
                    state.track(&user, "two-factor enabled", serde_json::json!({}));
                    let flash = Flash { recovery_codes: Some(&codes), ..Flash::default() };
                    return render(&state, &user, StatusCode::OK, flash).await;
                }
                Err(TwoFactorError::Other(error)) => return Err(error.into()),
                Err(error) => return failed(&state, &user, error).await,
            }
        }
        SettingsForm::Cancel => {
            two_factor::cancel(&state.pool, user.id).await?;
            return Ok(Redirect::to(&format!("{SETTINGS_PATH}?saved=cancelled")).into_response());
        }
        SettingsForm::RecoveryCodes { password } => {
            if !password_ok(&state, &user, password).await? {
                "Enter your current password to generate new recovery codes."
            } else {
                match two_factor::regenerate_recovery_codes(&state.pool, user.id).await {
                    Ok(codes) => {
                        let flash = Flash { recovery_codes: Some(&codes), ..Flash::default() };
                        return render(&state, &user, StatusCode::OK, flash).await;
                    }
                    Err(TwoFactorError::Other(error)) => return Err(error.into()),
                    Err(error) => return failed(&state, &user, error).await,
                }
            }
        }
        SettingsForm::Disable { password } => {
            if !password_ok(&state, &user, password).await? {
                "Enter your current password to turn off two-factor authentication."
            } else {
                if two_factor::disable(&state.pool, user.id).await? {
                    #[cfg(feature = "posthog-product")]
                    state.track(&user, "two-factor disabled", serde_json::json!({}));
                }
                return Ok(Redirect::to(&format!("{SETTINGS_PATH}?saved=off")).into_response());
            }
        }
    };
    render(&state, &user, StatusCode::UNPROCESSABLE_ENTITY, Flash { error: Some(error), ..Flash::default() }).await
}

async fn failed(state: &SharedState, user: &User, error: TwoFactorError) -> Result<Response, AppError> {
    let message = error.to_string();
    render(state, user, StatusCode::UNPROCESSABLE_ENTITY, Flash { error: Some(&message), ..Flash::default() }).await
}

// ---------------------------------------------------------------------------
// Sign-in
// ---------------------------------------------------------------------------

/// After the password check: park the sign-in and ask for a code.
pub async fn start_challenge(state: &SharedState, user: &User) -> Result<Response, AppError> {
    let token = two_factor::start_challenge(&state.pool, user.id).await?;
    let cookie = two_factor::cookie(&token, state.cfg.secure_cookies());
    Ok(([(header::SET_COOKIE, cookie)], Redirect::to(SIGN_IN_PATH)).into_response())
}

fn challenge_page(state: &SharedState, status: StatusCode, error: Option<&str>) -> Response {
    let page = views::Page {
        title: "Enter your code",
        path: SIGN_IN_PATH,
        user: None,
        body: views::two_factor::challenge(error),
    };
    let mut response = routes::html(status, views::layout(state, page));
    response.headers_mut().insert("x-robots-tag", axum::http::HeaderValue::from_static("noindex, nofollow"));
    response
}

pub async fn challenge_get(
    State(state): State<SharedState>,
    MaybeUser(user): MaybeUser,
    headers: HeaderMap,
) -> Result<Response, AppError> {
    if user.is_some() {
        return Ok(Redirect::to("/dashboard").into_response());
    }
    match two_factor::token_from_headers(&headers) {
        Some(token) if two_factor::challenge_pending(&state.pool, token).await? => {
            Ok(challenge_page(&state, StatusCode::OK, None))
        }
        _ => Ok(Redirect::to("/sign-in").into_response()),
    }
}

#[derive(Deserialize)]
pub struct ChallengeForm {
    #[serde(default)]
    code: String,
}

pub async fn challenge_post(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Form(form): Form<ChallengeForm>,
) -> Result<Response, AppError> {
    let Some(token) = two_factor::token_from_headers(&headers) else {
        return Ok(Redirect::to("/sign-in").into_response());
    };
    let secure = state.cfg.secure_cookies();
    match two_factor::finish_challenge(&state.pool, token, &form.code, OffsetDateTime::now_utc()).await {
        Ok(user) => {
            #[cfg(feature = "posthog")]
            crate::analytics::record_user(&user);
            let mut response = routes::start_session(&state, &user).await?;
            response.headers_mut().append(header::SET_COOKIE, two_factor::clear_cookie(secure));
            #[cfg(feature = "posthog-product")]
            state.track(&user, "user signed in", serde_json::json!({"two_factor": true}));
            Ok(response)
        }
        Err(ChallengeError::WrongCode { attempts_left }) => {
            let message = format!(
                "That code is not correct. {attempts_left} {} left before you have to sign in again.",
                if attempts_left == 1 { "attempt" } else { "attempts" }
            );
            Ok(challenge_page(&state, StatusCode::UNPROCESSABLE_ENTITY, Some(&message)))
        }
        // The challenge is gone either way: back to the password form, with the reason.
        Err(error @ (ChallengeError::NoChallenge | ChallengeError::TooManyAttempts)) => {
            let message = error.to_string();
            let mut response = routes::html(
                StatusCode::UNPROCESSABLE_ENTITY,
                routes::auth_page(&state, views::pages::AuthKind::SignIn, "", Some(&message)),
            );
            response.headers_mut().insert(header::SET_COOKIE, two_factor::clear_cookie(secure));
            Ok(response)
        }
        Err(ChallengeError::Other(error)) => Err(error.into()),
    }
}
