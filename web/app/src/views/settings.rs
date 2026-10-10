#[cfg(feature = "api")]
use crate::api_keys;
use crate::settings::Profile;
use app_auth::User;
use app_auth::passkeys::Passkey;
use maud::{Markup, html};
use time::macros::format_description;

pub use crate::settings::View;

pub fn page(profile: &Profile, view: &View<'_>, user: &User) -> Markup {
    let is_admin = user.is_admin;
    html! {
        section class="page settings" {
            h1 { "Account settings" }
            p class="lede" { "Your profile, passkeys, two-factor authentication, appearance, and account." }
            @if let Some(error) = view.flash.error { p class="alert" role="alert" { (error) } }
            @if let Some(notice) = view.flash.notice { p class="alert" role="status" { (notice) } }
            section class="panel appearance-panel" aria-labelledby="appearance-heading" {
                div { h2 id="appearance-heading" { "Appearance" } p class="muted small" { "Saved in this browser. System follows your device." } }
                (super::theme_choices())
            }
            section class="panel" aria-labelledby="profile-heading" {
                h2 id="profile-heading" { "Profile" }
                form class="form" method="post" action="/settings" {
                    input type="hidden" name="action" value="profile";
                    label { "Name" input name="name" autocomplete="name" maxlength="100" value=(profile.name); }
                    label { "Email address" input type="email" name="email" autocomplete="email" maxlength="254" required value=(profile.email); }
                    label { "Current password" input type="password" name="password" autocomplete="current-password" maxlength="256" aria-describedby="password-help"; }
                    p class="hint" id="password-help" { "Required only when changing your email. You’ll use the new email to sign in, and your other sessions will be signed out." }
                    button class="btn btn-primary" type="submit" { "Save changes" }
                }
            }
            (avatar_panel(view, user))
            (passkeys_panel(view.passkeys))
            (super::two_factor::panel(&view.two_factor))
            @if cfg!(feature = "stripe") {
                section class="panel" aria-labelledby="billing-heading" {
                    h2 id="billing-heading" { "Billing" }
                    @if is_admin {
                        p { strong { "Admin access" } }
                        p class="muted" { "Your admin role includes all paid features. No payment is required." }
                    } @else {
                        p class="muted" { "View your plan, payment status, and billing options." }
                    }
                    a class="btn settings-upgrade" href="/billing" { "Manage billing" }
                }
            }
            (api_keys_panel(view))
            section class="panel settings-danger" aria-labelledby="delete-heading" {
                h2 id="delete-heading" { "Delete account" }
                p class="muted" { "Permanently delete your account and local account data. This cannot be undone." }
                @if cfg!(feature = "stripe") {
                    p class="muted" { "Resolve pending payments and cancel subscriptions in Billing first. Scheduled cancellations must finish before deletion. Deleting an account does not issue refunds; Stripe retains payment records." }
                }
                details open[view.flash.confirmation.is_some()] {
                    summary { "Delete my account…" }
                    form class="form" method="post" action="/settings" {
                        input type="hidden" name="action" value="delete";
                        label { "Current password" input type="password" name="password" autocomplete="current-password" maxlength="256" required; }
                        label { "Type DELETE to confirm" input name="confirmation" autocomplete="off" pattern="DELETE" required value=(view.flash.confirmation.unwrap_or_default()); }
                        button class="btn btn-danger" type="submit" { "Permanently delete account" }
                    }
                }
            }
        }
    }
}

/// The first letter of the email, the stand-in for accounts without a picture.
pub fn initial(user: &User) -> String {
    user.email.chars().next().unwrap_or('A').to_uppercase().collect()
}

#[cfg(not(feature = "storage"))]
fn avatar_panel(_: &View<'_>, _: &User) -> Markup {
    html! {}
}

/// Profile pictures are the example of file storage; see `avatars.rs`.
#[cfg(feature = "storage")]
fn avatar_panel(view: &View<'_>, user: &User) -> Markup {
    html! {
        section class="panel" aria-labelledby="avatar-heading" {
            h2 id="avatar-heading" { "Profile picture" }
            div class="avatar-editor" {
                @match &view.avatar_url {
                    Some(url) => { img class="avatar-preview" src=(url) alt="Your current profile picture" width="96" height="96"; }
                    None => { div class="avatar-preview avatar-placeholder" aria-hidden="true" { (initial(user)) } }
                }
                div class="avatar-forms" {
                    form class="form" method="post" action="/settings/avatar" enctype="multipart/form-data" {
                        label { "New picture"
                            input type="file" name=(crate::avatars::FIELD) accept="image/png,image/jpeg,image/gif,image/webp" required;
                            span class="hint" { "PNG, JPEG, GIF or WebP, up to 2 MB. Shown next to your account menu." }
                        }
                        button class="btn btn-primary" type="submit" { "Upload picture" }
                    }
                    @if view.avatar_url.is_some() {
                        form method="post" action="/settings" {
                            input type="hidden" name="action" value="remove_avatar";
                            button class="btn" type="submit" { "Remove picture" }
                        }
                    }
                }
            }
        }
    }
}

#[cfg(not(feature = "api"))]
fn api_keys_panel(_: &View<'_>) -> Markup {
    html! {}
}

#[cfg(feature = "api")]
fn api_keys_panel(view: &View<'_>) -> Markup {
    let at_limit = view.keys.len() >= api_keys::MAX_PER_USER as usize;
    html! {
        section class="panel" aria-labelledby="api-keys-heading" {
            h2 id="api-keys-heading" { "API keys" }
            p class="muted" {
                "Interact with this platform from scripts and other apps through its API. A key has the same access as your account, so keep it secret. Revoking a key takes effect immediately."
                @if cfg!(feature = "docs") { " See the " a href="/docs/api" { "API guide" } "." }
                @if cfg!(all(feature = "docs", feature = "mcp")) { " The same keys connect coding agents to the " a href="/docs/mcp" { "MCP server" } "." }
            }
            @if let Some(token) = view.flash.new_key {
                div class="api-key-reveal" role="status" {
                    p { strong { "Copy your new API key now. It will not be shown again." } }
                    pre { code { (token) } }
                    p class="muted small" { "Send it as " code { "Authorization: Bearer " (token.get(..api_keys::PREFIX.len() + 4).unwrap_or_default()) "…" } " on every request." }
                }
            }
            @if view.keys.is_empty() {
                p class="muted small" { "You have no API keys." }
            } @else {
                div class="admin-table-wrap" {
                    table class="admin-table" {
                        thead { tr { th { "Name" } th { "Key" } th { "Created" } th { "Last used" } th { span class="visually-hidden" { "Actions" } } } }
                        tbody {
                            @for key in view.keys {
                                tr {
                                    th scope="row" { (key.name) }
                                    td { code { (key.prefix) "…" } }
                                    td { (super::short_date(key.created_at)) }
                                    td { @match key.last_used_at { Some(at) => (super::short_date(at)), None => "Never" } }
                                    td {
                                        form method="post" action="/settings" {
                                            input type="hidden" name="action" value="revoke_api_key";
                                            input type="hidden" name="id" value=(key.id);
                                            button class="btn btn-danger" type="submit" { "Revoke" }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            @if at_limit {
                p class="muted small" { "You have reached the limit of " (api_keys::MAX_PER_USER) " keys. Revoke one to create another." }
            } @else {
                form class="form" method="post" action="/settings" {
                    input type="hidden" name="action" value="create_api_key";
                    label { "Key name"
                        input name="name" maxlength=(api_keys::NAME_MAX) autocomplete="off" placeholder="e.g. laptop, CI, Claude Code";
                        span class="hint" { "Optional. Helps you recognize which key to revoke later." }
                    }
                    button class="btn btn-primary" type="submit" { "Create API key" }
                }
            }
        }
    }
}

/// Passkeys are added by `passkeys.js`; without it the form explains why.
pub fn passkeys_panel(passkeys: &[Passkey]) -> Markup {
    let day = format_description!("[day] [month repr:short] [year]");
    html! {
        section class="panel" aria-labelledby="passkeys-heading" {
            h2 id="passkeys-heading" { "Passkeys" }
            p class="muted" { "Sign in with Face ID, Touch ID, Windows Hello, or a security key instead of your password. A passkey only works on this site, so it cannot be phished." }
            @if passkeys.is_empty() {
                p class="muted small" { "No passkeys yet." }
            } @else {
                ul class="passkey-list" {
                    @for passkey in passkeys {
                        li {
                            div {
                                strong { (passkey.name) }
                                @if passkey.backed_up { " " span class="badge" { "Synced" } }
                                p class="muted small" {
                                    "Added " (passkey.created_at.format(day).unwrap_or_default())
                                    @match passkey.last_used_at {
                                        Some(used) => { " · Last used " (used.format(day).unwrap_or_default()) }
                                        None => { " · Never used" }
                                    }
                                }
                            }
                            form method="post" action="/settings" {
                                input type="hidden" name="action" value="remove_passkey";
                                input type="hidden" name="id" value=(passkey.id);
                                button class="btn btn-danger" type="submit" { "Remove" }
                            }
                        }
                    }
                }
            }
            form class="form" method="post" action="/settings" data-passkey-register data-options-url="/passkeys/register/options" data-register-url="/passkeys/register" {
                input type="hidden" name="action" value="passkey";
                label { "Passkey name" input name="name" maxlength="64" autocomplete="off" placeholder="e.g. Laptop"; }
                label { "Current password" input type="password" name="password" autocomplete="current-password" maxlength="256" required aria-describedby="passkey-help"; }
                p class="hint" id="passkey-help" { "Confirm your password, then follow your browser’s prompt to create the passkey." }
                button class="btn btn-primary" type="submit" { "Add a passkey" }
                p class="hint" data-passkey-status role="status" aria-live="polite" {}
            }
        }
    }
}
