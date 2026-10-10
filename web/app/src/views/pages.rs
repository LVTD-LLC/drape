use app_auth::User;
use maud::{Markup, html};
use time::macros::format_description;

pub fn home() -> Markup {
    html! {
        section class="hero" {
            span class="eyebrow" { "Your personal wardrobe" }
            h1 { "Make room for" br; "the clothes you love." }
            p class="lede" {
                "Drape helps you photograph, organize and rediscover your wardrobe on iPhone. "
                "Your photos and catalog stay on your device. "
                "The web library is coming later."
            }
        }
    }
}

pub fn dashboard(user: &User) -> Markup {
    let billing_enabled = cfg!(feature = "stripe");
    let joined = user.created_at.format(format_description!("[day] [month repr:long] [year]")).unwrap_or_default();
    html! {
        section class="page" {
            h1 { "Dashboard" }
            @if billing_enabled { a class="btn" href="/billing" { "Billing" } }
            p class="lede" { "You're signed in as " strong { (user.email) } "." }
            div class="panel" {
                dl {
                    dt { "Email" } dd { (user.email) }
                    dt { "Member since" } dd { (joined) }
                    dt { "User ID" } dd { code { (user.id) } }
                }
            }
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum AuthKind {
    SignUp,
    SignIn,
}

pub fn auth(kind: AuthKind, email: &str, error: Option<&str>) -> Markup {
    let (heading, action, button, autocomplete, email_autocomplete) = match kind {
        AuthKind::SignUp => ("Create your account", "/sign-up", "Create account", "new-password", "email"),
        // `webauthn` lets the browser offer saved passkeys in the email field's autofill.
        AuthKind::SignIn => ("Welcome back", "/sign-in", "Sign in", "current-password", "username webauthn"),
    };
    html! {
        section class="page narrow" {
            h1 { (heading) }
            @if let Some(e) = error { p class="alert" role="alert" { (e) } }
            form class="form" method="post" action=(action) {
                label { "Email"
                    input type="email" name="email" value=(email) required autocomplete=(email_autocomplete) autofocus;
                }
                label { "Password"
                    input type="password" name="password" required minlength="8" autocomplete=(autocomplete);
                }
                button class="btn btn-primary" type="submit" { (button) }
            }
            @if kind == AuthKind::SignIn {
                // Hidden until passkeys.js confirms the browser supports WebAuthn.
                div class="passkey-signin" hidden data-passkey-signin data-options-url="/passkeys/sign-in/options" data-sign-in-url="/passkeys/sign-in" {
                    p class="muted small" { "or" }
                    button class="btn" type="button" data-passkey-button { (key_icon()) "Sign in with a passkey" }
                    p class="hint" data-passkey-status role="status" aria-live="polite" {}
                }
            }
            p class="muted small switch" {
                @match kind {
                    AuthKind::SignUp => { "Already have an account? " a href="/sign-in" { "Sign in" } }
                    AuthKind::SignIn => { "New here? " a href="/sign-up" { "Create an account" } }
                }
            }
        }
    }
}

fn key_icon() -> Markup {
    html! { svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" {
        circle cx="7.5" cy="15.5" r="4.5" {}
        path d="M10.8 12.2 21 2m-3 3 3 3m-6 0 3 3" {}
    } }
}

pub fn not_found() -> Markup {
    html! {
        section class="page" {
            h1 { "Page not found" }
            p class="lede" { "There's nothing at this address." }
            a class="btn" href="/" { "Back home" }
        }
    }
}

#[cfg(feature = "stripe")]
pub fn billing(
    status: &crate::billing::BillingStatus,
    config: Option<&crate::billing::Config>,
    message: Option<&str>,
) -> Markup {
    html! {
        section class="page narrow" {
            h1 { "Billing" }
            @if let Some(message) = message { p class="alert" role="status" { (message) } }
            @if status.is_admin {
                p { strong { "Admin access" } }
                p { "Your admin role includes all paid features. No payment is required." }
                @if status.subscription_status.as_deref().is_some_and(|s| !matches!(s, "canceled" | "incomplete_expired")) {
                    p class="muted" { "Your existing subscription is unchanged. Use Manage billing to cancel it if you no longer need it." }
                }
            }
            @if status.paid { p { "Your one-time purchase is confirmed." } }
            @if let Some(subscription) = &status.subscription_status {
                p { "Subscription: " strong { (subscription) } }
                @if status.cancel_at_period_end { p { "Your subscription will end at the end of the current billing period." } }
            }
            @if let Some(config) = config {
                @if !status.is_admin && !status.paid && !status.subscription_status.as_deref().is_some_and(|s| !matches!(s, "canceled" | "incomplete_expired")) {
                    p class="lede" { "Choose a plan. Review the price and payment details securely on Stripe." }
                    form class="form" method="post" action="/billing" {
                        @if config.subscriptions_enabled() { button class="btn btn-primary" name="mode" value="subscription" type="submit" { "Subscribe" } }
                        @if config.payments_enabled() { button class="btn" name="mode" value="payment" type="submit" { "Pay once" } }
                    }
                }
                @if status.has_customer {
                    form method="post" action="/billing/portal" { button class="btn" type="submit" { "Manage billing" } }
                    p class="muted small" { "Update your payment method, view invoices, or cancel your subscription on Stripe." }
                }
            } @else if !status.is_admin { p { "Billing is not configured yet." } }
            a href="/dashboard" { "Back to dashboard" }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn homepage_content_and_headings_are_readable_without_javascript() {
        // This fragment is the homepage's main content, rendered without scripts.
        // Inspect Maud's generated tags and text without adding a parser dependency.
        let html = home().into_string();
        let mut in_paragraph = false;
        let mut prose = String::new();
        let mut previous = 0;
        let mut h1_count = 0;
        for element in html.split('<').skip(1) {
            let (tag, text) = element.split_once('>').unwrap();
            let tag = tag.split_ascii_whitespace().next().unwrap();
            match tag {
                "p" => in_paragraph = true,
                "/p" => {
                    in_paragraph = false;
                    prose.push(' ');
                }
                _ => {}
            }
            if in_paragraph {
                prose.push_str(text);
            }
            if let [b'h', level @ b'1'..=b'6'] = tag.as_bytes() {
                let level = level - b'0';
                assert!(level <= previous + 1, "heading hierarchy skips H{previous} to H{level}");
                assert!(!text.trim().is_empty(), "headings must have text");
                h1_count += usize::from(level == 1);
                previous = level;
            }
        }
        assert_eq!(h1_count, 1, "homepage needs exactly one H1");
        let prose = prose.split_whitespace().collect::<Vec<_>>().join(" ");
        assert!(prose.contains("Your photos and catalog stay on your device."));
        assert!(prose.contains("The web library is coming later."));
    }
}
