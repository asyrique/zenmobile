/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

//! A download-only sync engine for the `spaces` collection.
//!
//! Desktop never needs anything from us, and the desktop applier treats
//! every incoming record as authoritative (its `_reconcile` always accepts),
//! so uploading is all risk and no reward until mobile can edit Spaces.

use crate::record::SpacesRecord;
use crate::storage::{
    IncomingChange, COLLECTION_SYNCID_META_KEY, GLOBAL_SYNCID_META_KEY, LAST_SYNC_META_KEY,
};
use crate::store::ZenSpacesStore;
use crate::COLLECTION_NAME;
use anyhow::Result;
use error_support::{info, warn};
use std::sync::Arc;
use sync15::bso::{IncomingBso, IncomingKind, OutgoingBso};
use sync15::engine::{CollSyncIds, CollectionRequest, EngineSyncAssociation, SyncEngine};
use sync15::{telemetry, CollectionName, ServerTimestamp};
use sync_guid::Guid;

pub struct ZenSpacesEngine {
    store: Arc<ZenSpacesStore>,
}

impl ZenSpacesEngine {
    pub fn new(store: Arc<ZenSpacesStore>) -> Self {
        Self { store }
    }

    fn set_last_sync(&self, ts: ServerTimestamp) -> Result<()> {
        self.store
            .storage
            .lock()
            .put_meta(LAST_SYNC_META_KEY, &ts.as_millis().to_string())?;
        Ok(())
    }
}

impl SyncEngine for ZenSpacesEngine {
    fn collection_name(&self) -> CollectionName {
        COLLECTION_NAME.into()
    }

    fn stage_incoming(&self, inbound: Vec<IncomingBso>, telem: &mut telemetry::Engine) -> Result<()> {
        let mut incoming_telemetry = telemetry::EngineIncoming::new();
        let mut changes = Vec::with_capacity(inbound.len());
        for bso in inbound {
            let id = bso.envelope.id.to_string();
            let modified = bso.envelope.modified.as_millis();
            match bso.into_content::<SpacesRecord>().kind {
                IncomingKind::Content(mut record) => {
                    // The envelope id is the one the server indexes by.
                    record.id = id;
                    changes.push(IncomingChange::Upsert { record, modified });
                    incoming_telemetry.applied(1);
                }
                IncomingKind::Tombstone => {
                    changes.push(IncomingChange::Delete { id });
                    incoming_telemetry.applied(1);
                }
                IncomingKind::Malformed => {
                    warn!("Ignoring malformed spaces record {}", id);
                    incoming_telemetry.failed(1);
                }
            }
        }
        telem.incoming(incoming_telemetry);
        self.store.storage.lock().apply_changes(changes)?;
        Ok(())
    }

    fn apply(&self, timestamp: ServerTimestamp, _telem: &mut telemetry::Engine) -> Result<Vec<OutgoingBso>> {
        self.set_last_sync(timestamp)?;
        Ok(vec![])
    }

    fn set_uploaded(&self, new_timestamp: ServerTimestamp, ids: Vec<Guid>) -> Result<()> {
        debug_assert!(ids.is_empty(), "the spaces engine never uploads");
        self.set_last_sync(new_timestamp)
    }

    fn get_collection_request(&self, server_timestamp: ServerTimestamp) -> Result<Option<CollectionRequest>> {
        let since = self.last_sync()?.unwrap_or_default();
        Ok(if since == server_timestamp {
            None
        } else {
            Some(
                CollectionRequest::new(COLLECTION_NAME.into())
                    .full()
                    .newer_than(since),
            )
        })
    }

    fn get_sync_assoc(&self) -> Result<EngineSyncAssociation> {
        let storage = self.store.storage.lock();
        let global = storage.get_meta(GLOBAL_SYNCID_META_KEY)?;
        let coll = storage.get_meta(COLLECTION_SYNCID_META_KEY)?;
        Ok(match (global, coll) {
            (Some(global), Some(coll)) => EngineSyncAssociation::Connected(CollSyncIds {
                global: Guid::from_string(global),
                coll: Guid::from_string(coll),
            }),
            _ => EngineSyncAssociation::Disconnected,
        })
    }

    fn reset(&self, assoc: &EngineSyncAssociation) -> Result<()> {
        info!("Resetting spaces engine: {:?}", assoc);
        // Our records are only a mirror of the server, so a reset (new sync
        // ids, a node reassignment, a disconnect) drops them and the next
        // sync downloads everything again.
        let storage = self.store.storage.lock();
        storage.wipe_records()?;
        storage.delete_meta(LAST_SYNC_META_KEY)?;
        match assoc {
            EngineSyncAssociation::Disconnected => {
                storage.delete_meta(GLOBAL_SYNCID_META_KEY)?;
                storage.delete_meta(COLLECTION_SYNCID_META_KEY)?;
            }
            EngineSyncAssociation::Connected(ids) => {
                storage.put_meta(GLOBAL_SYNCID_META_KEY, ids.global.as_str())?;
                storage.put_meta(COLLECTION_SYNCID_META_KEY, ids.coll.as_str())?;
            }
        }
        Ok(())
    }

    fn wipe(&self) -> Result<()> {
        self.reset(&EngineSyncAssociation::Disconnected)
    }

    fn last_sync(&self) -> Result<Option<ServerTimestamp>> {
        let storage = self.store.storage.lock();
        Ok(ZenSpacesStore::last_sync_in(&storage)?.map(ServerTimestamp))
    }

    fn reset_last_sync(&self) -> Result<()> {
        self.store.storage.lock().delete_meta(LAST_SYNC_META_KEY)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn incoming(id: &str, kind: &str, data: serde_json::Value, ts: i64) -> IncomingBso {
        IncomingBso::from_test_content_ts(
            json!({"id": id, "kind": kind, "data": data}),
            ServerTimestamp(ts),
        )
    }

    #[test]
    fn downloads_and_never_uploads() {
        let store = ZenSpacesStore::new_in_memory();
        let engine = store.sync_engine();
        let mut telem = telemetry::Engine::new("spaces");

        assert_eq!(engine.last_sync().unwrap(), None);
        assert!(engine
            .get_collection_request(ServerTimestamp(1000))
            .unwrap()
            .is_some());

        engine
            .stage_incoming(
                vec![
                    incoming("{s}", "space", json!({"uuid": "{s}", "name": "Work", "children": ["t"]}), 900),
                    incoming("t", "tab", json!({"tabId": "t", "url": "https://a.example/", "workspaceUuid": "{s}", "pinned": true}), 900),
                ],
                &mut telem,
            )
            .unwrap();
        let outgoing = engine.apply(ServerTimestamp(1000), &mut telem).unwrap();
        assert!(outgoing.is_empty());

        let snap = store.snapshot().unwrap();
        assert_eq!(snap.spaces[0].name, "Work");
        assert_eq!(snap.spaces[0].rows.len(), 1);
        assert_eq!(snap.last_sync_millis, Some(1000));

        // Nothing changed on the server: no request at all.
        assert!(engine
            .get_collection_request(ServerTimestamp(1000))
            .unwrap()
            .is_none());
    }

    #[test]
    fn tombstones_delete() {
        let store = ZenSpacesStore::new_in_memory();
        let engine = store.sync_engine();
        let mut telem = telemetry::Engine::new("spaces");
        engine
            .stage_incoming(vec![incoming("{s}", "space", json!({"uuid": "{s}", "name": "Gone"}), 1)], &mut telem)
            .unwrap();
        engine
            .stage_incoming(vec![IncomingBso::new_test_tombstone(Guid::new("{s}"))], &mut telem)
            .unwrap();
        assert!(store.snapshot().unwrap().spaces.is_empty());
    }

    #[test]
    fn reset_drops_the_mirror() {
        let store = ZenSpacesStore::new_in_memory();
        let engine = store.sync_engine();
        let mut telem = telemetry::Engine::new("spaces");
        engine
            .stage_incoming(vec![incoming("{s}", "space", json!({"uuid": "{s}", "name": "A"}), 1)], &mut telem)
            .unwrap();
        engine.apply(ServerTimestamp(5), &mut telem).unwrap();

        let ids = CollSyncIds {
            global: Guid::new("global"),
            coll: Guid::new("coll"),
        };
        engine
            .reset(&EngineSyncAssociation::Connected(ids.clone()))
            .unwrap();
        assert!(store.snapshot().unwrap().spaces.is_empty());
        assert_eq!(engine.last_sync().unwrap(), None);
        assert_eq!(
            engine.get_sync_assoc().unwrap(),
            EngineSyncAssociation::Connected(ids)
        );

        engine.wipe().unwrap();
        assert_eq!(
            engine.get_sync_assoc().unwrap(),
            EngineSyncAssociation::Disconnected
        );
    }
}
