/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

//! Account configuration, in one place for both apps.
//!
//! Mozilla does not register third-party Sync clients, so we sign in as
//! Firefox for Android (see docs/decisions/0003-firefox-oauth-client.md).
//! Everything that depends on that choice lives in this file; moving to our
//! own client id or a self-hosted FxA is a change here only.

use fxa_client::{DeviceCapability, DeviceConfig, DeviceType, FxaConfig, FxaServer};
use url::Url;

/// Firefox for Android's public OAuth client id.
pub const FIREFOX_ANDROID_CLIENT_ID: &str = "a2270f727f45f648";

const OLD_SYNC_SCOPE: &str = "https://identity.mozilla.com/apps/oldsync";
const PROFILE_SCOPE: &str = "profile";

fn redirect_uri(server: &FxaServer, client_id: &str) -> String {
    format!("{}/oauth/success/{}", server.content_url(), client_id)
}

/// The config to construct `FirefoxAccount` with.
///
/// The redirect is FxA's own "success" page rather than a custom scheme:
/// the app loads the sign-in flow in its own web view and catches the
/// navigation to it (see [`zen_parse_oauth_redirect`]).
#[uniffi::export]
pub fn zen_fxa_config() -> FxaConfig {
    let server = FxaServer::Release;
    FxaConfig {
        redirect_uri: redirect_uri(&server, FIREFOX_ANDROID_CLIENT_ID),
        server,
        client_id: FIREFOX_ANDROID_CLIENT_ID.to_string(),
        token_server_url_override: None,
    }
}

/// Scopes to request when beginning the OAuth or pairing flow.
#[uniffi::export]
pub fn zen_sync_scopes() -> Vec<String> {
    vec![PROFILE_SCOPE.to_string(), OLD_SYNC_SCOPE.to_string()]
}

/// How this device appears in the account's device list (and in desktop's
/// "Send tab to device" menu).
#[uniffi::export]
pub fn zen_device_config(name: String) -> DeviceConfig {
    DeviceConfig {
        name,
        device_type: DeviceType::Mobile,
        capabilities: vec![DeviceCapability::SendTab, DeviceCapability::CloseTabs],
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct OAuthRedirect {
    pub code: String,
    pub state: String,
}

/// If `url` is the end of the sign-in flow, returns what to hand to
/// `FxaEvent::CompleteOAuthFlow`. The web view should cancel that
/// navigation and call this for every main-frame navigation it sees.
#[uniffi::export]
pub fn zen_parse_oauth_redirect(url: String) -> Option<OAuthRedirect> {
    let expected = Url::parse(&zen_fxa_config().redirect_uri).ok()?;
    let url = Url::parse(&url).ok()?;
    if url.origin() != expected.origin() || url.path() != expected.path() {
        return None;
    }
    let param = |name: &str| {
        url.query_pairs()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.into_owned())
            .filter(|v| !v.is_empty())
    };
    Some(OAuthRedirect {
        code: param("code")?,
        state: param("state")?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redirect_matches_config() {
        let config = zen_fxa_config();
        assert_eq!(
            config.redirect_uri,
            "https://accounts.firefox.com/oauth/success/a2270f727f45f648"
        );
        assert_eq!(
            zen_parse_oauth_redirect(format!("{}?code=abc&state=xyz", config.redirect_uri)),
            Some(OAuthRedirect {
                code: "abc".into(),
                state: "xyz".into()
            })
        );
    }

    #[test]
    fn ignores_other_urls() {
        for url in [
            "https://accounts.firefox.com/signin?code=abc&state=xyz",
            "https://evil.example/oauth/success/a2270f727f45f648?code=abc&state=xyz",
            "https://accounts.firefox.com/oauth/success/a2270f727f45f648?code=abc",
            "https://accounts.firefox.com/oauth/success/a2270f727f45f648?code=&state=xyz",
            "not a url",
        ] {
            assert_eq!(zen_parse_oauth_redirect(url.into()), None, "{url}");
        }
    }
}
