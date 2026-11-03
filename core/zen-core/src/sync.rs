/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

//! Syncs the collections Zen Mobile cares about in one pass.
//!
//! This is application-services' `sync_manager` cut down to our engines:
//! that crate only knows Mozilla's engines and can't be handed Zen's
//! `spaces` engine, so we drive sync15 ourselves. It also takes the
//! `FirefoxAccount` directly and fetches the token and sync key itself, so
//! neither app has to repeat that dance.

use error_support::{info, warn};
use fxa_client::FirefoxAccount;
use parking_lot::Mutex;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use sync15::client::{
    sync_multiple_with_command_processor, MemoryCachedState, ServiceStatus,
    Sync15StorageClientInit, SyncRequestInfo,
};
use sync15::clients_engine::{Command, CommandProcessor, CommandStatus, Settings};
use sync15::engine::{EngineSyncAssociation, SyncEngine, SyncEngineId};
use sync15::{DeviceType, KeyBundle};
use tabs::{TabsEngine, TabsStore};
use zen_spaces::ZenSpacesStore;

const OLD_SYNC_SCOPE: &str = "https://identity.mozilla.com/apps/oldsync";

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ZenSyncReason {
    Startup,
    Scheduled,
    /// The user asked (pull to refresh). Ignores server backoff.
    User,
    /// Woken by a push message, e.g. desktop sent a tab.
    Push,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ZenSyncParams {
    pub reason: ZenSyncReason,
    /// `ZenSyncResult::persisted_state` from the previous sync, if any.
    pub persisted_state: Option<String>,
    /// Shown on desktop next to this device's tabs.
    pub device_name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ZenSyncStatus {
    Ok,
    NetworkError,
    ServiceError,
    /// The account needs attention; check `FirefoxAccount::get_state`.
    AuthError,
    /// The server asked us to back off; try after `next_sync_allowed_at_millis`.
    BackedOff,
    OtherError,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ZenSyncResult {
    pub status: ZenSyncStatus,
    pub successful: Vec<String>,
    /// Engine name to error message.
    pub failures: HashMap<String, String>,
    /// Opaque; hand back in the next `ZenSyncParams`.
    pub persisted_state: String,
    pub next_sync_allowed_at_millis: Option<i64>,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ZenSyncError {
    #[error("A sync is already running")]
    Busy,
    /// Not signed in, the device isn't registered yet, or the account has
    /// no sync key. Sync can't start until the account is fixed.
    #[error("Account not ready to sync: {reason}")]
    AccountNotReady { reason: String },
}

#[derive(uniffi::Object)]
pub struct ZenSyncManager {
    tabs: Arc<TabsStore>,
    spaces: Arc<ZenSpacesStore>,
    mem_cached_state: Mutex<Option<MemoryCachedState>>,
}

#[uniffi::export]
impl ZenSyncManager {
    #[uniffi::constructor]
    pub fn new(tabs: Arc<TabsStore>, spaces: Arc<ZenSpacesStore>) -> Self {
        Self {
            tabs,
            spaces,
            mem_cached_state: Mutex::new(None),
        }
    }

    /// Syncs `clients`, `tabs`, `spaces`, and `history` and `bookmarks` once
    /// Places is registered. Blocking; call it off the main
    /// thread.
    pub fn sync(
        &self,
        account: Arc<FirefoxAccount>,
        params: ZenSyncParams,
    ) -> Result<ZenSyncResult, ZenSyncError> {
        let Some(mut state) = self.mem_cached_state.try_lock() else {
            return Err(ZenSyncError::Busy);
        };
        let mem_state = state.get_or_insert_with(MemoryCachedState::default);

        if backoff_in_effect(mem_state.get_next_sync_after(), params.reason) {
            info!("Under server backoff; skipping {:?} sync", params.reason);
            return Ok(ZenSyncResult {
                status: ZenSyncStatus::BackedOff,
                successful: vec![],
                failures: HashMap::new(),
                persisted_state: params.persisted_state.unwrap_or_default(),
                next_sync_allowed_at_millis: mem_state.get_next_sync_after().map(to_millis),
            });
        }

        let result = self.sync_once(&account, &params, mem_state)?;
        if result.status != ZenSyncStatus::AuthError {
            return Ok(result);
        }
        // Usually an expired cached token: drop it and try once more, as
        // Firefox for Android does, before telling the app.
        warn!("Sync auth error; retrying with a fresh token");
        account.clear_access_token_cache();
        let retry = self.sync_once(
            &account,
            &ZenSyncParams {
                persisted_state: Some(result.persisted_state),
                ..params
            },
            mem_state,
        )?;
        if retry.status == ZenSyncStatus::AuthError {
            account.on_auth_issues();
        }
        Ok(retry)
    }

    /// Forget all synced data, e.g. after signing out.
    pub fn disconnect(&self) {
        for engine in self.engines() {
            if let Err(e) = engine.reset(&EngineSyncAssociation::Disconnected) {
                warn!("Failed to reset {}: {}", engine.collection_name(), e);
            }
        }
        *self.mem_cached_state.lock() = None;
    }
}

impl ZenSyncManager {
    fn engines(&self) -> Vec<Box<dyn SyncEngine>> {
        let mut engines: Vec<Box<dyn SyncEngine>> = vec![
            Box::new(TabsEngine::new(Arc::clone(&self.tabs))),
            Box::new(self.spaces.sync_engine()),
        ];
        // History and bookmarks, once the app has opened Places and called
        // PlacesApi.registerWithSyncManager() (as Firefox's apps do).
        for id in [SyncEngineId::History, SyncEngineId::Bookmarks] {
            if let Some(engine) = places::get_registered_sync_engine(&id) {
                engines.push(engine);
            }
        }
        // Saved passwords, once the app has opened its LoginStore and called
        // registerWithSyncManager().
        if let Some(engine) = logins::get_registered_sync_engine(&SyncEngineId::Passwords) {
            engines.push(engine);
        }
        engines
    }

    fn sync_once(
        &self,
        account: &FirefoxAccount,
        params: &ZenSyncParams,
        mem_state: &mut MemoryCachedState,
    ) -> Result<ZenSyncResult, ZenSyncError> {
        let not_ready = |reason: String| ZenSyncError::AccountNotReady { reason };
        let token = account
            .get_access_token(OLD_SYNC_SCOPE, true)
            .map_err(|e| not_ready(e.to_string()))?;
        let key = token
            .key
            .ok_or_else(|| not_ready("no scoped key for the sync scope".into()))?;
        let tokenserver_url = account
            .get_token_server_endpoint_url()
            .map_err(|e| not_ready(e.to_string()))
            .and_then(|u| url::Url::parse(&u).map_err(|e| not_ready(e.to_string())))?;
        let device_id = account
            .get_current_device_id()
            .map_err(|e| not_ready(format!("device not registered: {e}")))?;
        let root_key = KeyBundle::from_ksync_base64(&key.k).map_err(|e| not_ready(e.to_string()))?;

        let client_init = Sync15StorageClientInit {
            key_id: key.kid,
            access_token: token.token,
            tokenserver_url,
        };
        let processor = ZenCommandProcessor {
            settings: Settings {
                fxa_device_id: device_id,
                device_name: params.device_name.clone(),
                device_type: DeviceType::Mobile,
            },
            manager: self,
        };
        let engines = self.engines();
        let engine_refs: Vec<&dyn SyncEngine> = engines.iter().map(|e| &**e).collect();
        let mut persisted = params.persisted_state.clone();

        let result = sync_multiple_with_command_processor(
            Some(&processor),
            &engine_refs,
            &mut persisted,
            mem_state,
            &client_init,
            &root_key,
            &interrupt_support::ShutdownInterruptee,
            Some(SyncRequestInfo {
                engines_to_state_change: None,
                is_user_action: params.reason == ZenSyncReason::User,
            }),
        );
        info!("Sync finished: {:?}", result.service_status);

        let mut successful = vec![];
        let mut failures = HashMap::new();
        for (engine, r) in result.engine_results {
            match r {
                Ok(()) => successful.push(engine),
                Err(e) => {
                    failures.insert(engine, e.to_string());
                }
            }
        }
        successful.sort();
        Ok(ZenSyncResult {
            status: result.service_status.into(),
            successful,
            failures,
            persisted_state: persisted.unwrap_or_default(),
            next_sync_allowed_at_millis: result.next_sync_after.map(to_millis),
        })
    }
}

fn backoff_in_effect(next_sync_after: Option<SystemTime>, reason: ZenSyncReason) -> bool {
    reason != ZenSyncReason::User && next_sync_after.is_some_and(|t| t > SystemTime::now())
}

fn to_millis(t: SystemTime) -> i64 {
    t.duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or_default()
}

impl From<ServiceStatus> for ZenSyncStatus {
    fn from(s: ServiceStatus) -> Self {
        match s {
            ServiceStatus::Ok => Self::Ok,
            ServiceStatus::NetworkError => Self::NetworkError,
            ServiceStatus::ServiceError => Self::ServiceError,
            ServiceStatus::AuthenticationError => Self::AuthError,
            ServiceStatus::BackedOff => Self::BackedOff,
            ServiceStatus::Interrupted | ServiceStatus::OtherError => Self::OtherError,
        }
    }
}

/// Applies wipe/reset commands other devices write to our client record.
struct ZenCommandProcessor<'a> {
    settings: Settings,
    manager: &'a ZenSyncManager,
}

impl CommandProcessor for ZenCommandProcessor<'_> {
    fn settings(&self) -> &Settings {
        &self.settings
    }

    fn apply_incoming_command(&self, command: Command) -> anyhow::Result<CommandStatus> {
        let engines = self.manager.engines();
        let matching: Vec<&Box<dyn SyncEngine>> = match &command {
            Command::Wipe(name) | Command::Reset(name) => engines
                .iter()
                .filter(|e| e.collection_name() == name.as_str())
                .collect(),
            Command::ResetAll => engines.iter().collect(),
        };
        if matching.is_empty() {
            return Ok(CommandStatus::Unsupported);
        }
        for engine in matching {
            match command {
                Command::Wipe(_) => engine.wipe()?,
                _ => engine.reset(&EngineSyncAssociation::Disconnected)?,
            }
        }
        Ok(CommandStatus::Applied)
    }

    fn fetch_outgoing_commands(&self) -> anyhow::Result<HashSet<Command>> {
        Ok(HashSet::new())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn backoff_only_blocks_automatic_syncs() {
        let later = Some(SystemTime::now() + Duration::from_secs(60));
        let earlier = Some(SystemTime::now() - Duration::from_secs(60));
        assert!(backoff_in_effect(later, ZenSyncReason::Scheduled));
        assert!(backoff_in_effect(later, ZenSyncReason::Push));
        assert!(!backoff_in_effect(later, ZenSyncReason::User));
        assert!(!backoff_in_effect(earlier, ZenSyncReason::Scheduled));
        assert!(!backoff_in_effect(None, ZenSyncReason::Startup));
    }

    #[test]
    fn reset_command_targets_named_engine() {
        let manager = ZenSyncManager::new(
            Arc::new(TabsStore::new_with_mem_path("reset_command_targets_named_engine")),
            ZenSpacesStore::new_in_memory(),
        );
        let processor = ZenCommandProcessor {
            settings: Settings {
                fxa_device_id: "device".into(),
                device_name: "Phone".into(),
                device_type: DeviceType::Mobile,
            },
            manager: &manager,
        };
        assert_eq!(
            processor
                .apply_incoming_command(Command::Reset("spaces".into()))
                .unwrap(),
            CommandStatus::Applied
        );
        assert_eq!(
            processor
                .apply_incoming_command(Command::Wipe("addresses".into()))
                .unwrap(),
            CommandStatus::Unsupported
        );
    }

    // One test for both: registration is process-wide, so separate tests
    // running in parallel would see each other's engines.
    #[test]
    fn places_and_logins_engines_join_once_registered() {
        let manager = ZenSyncManager::new(
            Arc::new(TabsStore::new_with_mem_path("engines_join_once_registered")),
            ZenSpacesStore::new_in_memory(),
        );
        let names = || -> Vec<String> {
            manager
                .engines()
                .iter()
                .map(|e| e.collection_name().to_string())
                .collect()
        };
        assert_eq!(names(), ["tabs", "spaces"]);

        let dir = std::env::temp_dir();
        let places_path = dir.join(format!("zen-places-{}.sqlite", std::process::id()));
        let api = places::PlacesApi::new(&places_path).unwrap();
        api.clone().register_with_sync_manager();

        let logins_path = dir.join(format!("zen-logins-{}.sqlite", std::process::id()));
        crate::zen_initialize(); // NSS, for the logins key
        let key = db_crypto::create_key().unwrap();
        let store = logins::create_login_store_with_static_key_manager(
            logins_path.to_string_lossy().into_owned(),
            key,
        );
        store.clone().register_with_sync_manager();

        assert_eq!(names(), ["tabs", "spaces", "history", "bookmarks", "passwords"]);
        drop(api);
        drop(store);
        let _ = std::fs::remove_file(&places_path);
        let _ = std::fs::remove_file(&logins_path);
    }
}
