/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

use crate::engine::ZenSpacesEngine;
use crate::error::{Result, ZenSpacesError};
use crate::snapshot::{build_snapshot, ZenSpacesSnapshot};
use crate::storage::{SpacesStorage, LAST_SYNC_META_KEY};
use parking_lot::Mutex;
use std::sync::Arc;

/// The local mirror of desktop's Spaces. Sync it with `ZenSyncManager`
/// (zen-core), read it with [`ZenSpacesStore::snapshot`].
#[derive(uniffi::Object)]
pub struct ZenSpacesStore {
    pub(crate) storage: Mutex<SpacesStorage>,
}

#[uniffi::export]
impl ZenSpacesStore {
    #[uniffi::constructor]
    pub fn new(path: String) -> Result<Arc<Self>, ZenSpacesError> {
        Ok(Arc::new(Self {
            storage: Mutex::new(SpacesStorage::open(path)?),
        }))
    }

    /// Everything the Spaces UI needs, resolved and ordered.
    pub fn snapshot(&self) -> Result<ZenSpacesSnapshot, ZenSpacesError> {
        let storage = self.storage.lock();
        let records = storage.all_records()?;
        Ok(build_snapshot(&records, Self::last_sync_in(&storage)?))
    }
}

impl ZenSpacesStore {
    pub fn new_in_memory() -> Arc<Self> {
        Arc::new(Self {
            storage: Mutex::new(SpacesStorage::open_in_memory().expect("in-memory sqlite")),
        })
    }

    /// A sync engine for this store, to hand to sync15.
    pub fn sync_engine(self: &Arc<Self>) -> ZenSpacesEngine {
        ZenSpacesEngine::new(Arc::clone(self))
    }

    pub(crate) fn last_sync_in(storage: &SpacesStorage) -> Result<Option<i64>> {
        Ok(storage
            .get_meta(LAST_SYNC_META_KEY)?
            .and_then(|v| v.parse().ok()))
    }
}
