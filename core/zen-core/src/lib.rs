/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

//! The single native library Zen Mobile links, on both platforms.
//!
//! Like application-services' "megazords", every Rust component the app uses
//! is linked into this one crate, so there is one copy of the Rust std,
//! NSS and SQLite in the process. The re-exports below are what keeps each
//! component's FFI symbols alive; `uniffi-bindgen --library` then generates
//! one Swift module per component from the built library.

pub use fxa_client;
pub use init_rust_components;
pub use places;
pub use rust_log_forwarder;
pub use tabs;
pub use viaduct_backend_rust;
pub use zen_spaces;

mod config;
mod sync;

pub use config::{
    zen_device_config, zen_fxa_config, zen_parse_oauth_redirect, zen_sync_scopes,
    OAuthRedirect, FIREFOX_ANDROID_CLIENT_ID,
};
pub use sync::{
    ZenSyncError, ZenSyncManager, ZenSyncParams, ZenSyncReason, ZenSyncResult, ZenSyncStatus,
};

use std::sync::Once;

/// Must be called once, before any other call into the core: initializes
/// NSS and installs the HTTP backend that sync and accounts use.
#[uniffi::export]
pub fn zen_initialize() {
    static INIT: Once = Once::new();
    INIT.call_once(|| {
        init_rust_components::initialize();
        viaduct_backend_rust::viaduct_init_backend_rust();
    });
}

uniffi::setup_scaffolding!("zen_core");
