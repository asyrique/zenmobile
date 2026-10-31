/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

//! A local mirror of the `spaces` collection. We store records verbatim and
//! resolve them into a sidebar tree on read: the tree is cheap to build, and
//! keeping the raw records means a model fix never needs a re-download.

use crate::error::Result;
use crate::record::SpacesRecord;
use rusqlite::{params, Connection, OptionalExtension};
use std::path::Path;

pub(crate) const LAST_SYNC_META_KEY: &str = "last_sync_time";
pub(crate) const GLOBAL_SYNCID_META_KEY: &str = "global_sync_id";
pub(crate) const COLLECTION_SYNCID_META_KEY: &str = "spaces_sync_id";

const SCHEMA: &str = "
    CREATE TABLE IF NOT EXISTS records (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,
        server_modified INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
";

/// One change from the server, already decrypted.
pub(crate) enum IncomingChange {
    Upsert {
        record: SpacesRecord,
        modified: i64,
    },
    Delete {
        id: String,
    },
}

pub(crate) struct SpacesStorage {
    conn: Connection,
}

impl SpacesStorage {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        Self::init(Connection::open(path)?)
    }

    pub fn open_in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self> {
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self { conn })
    }

    pub fn apply_changes(&mut self, changes: Vec<IncomingChange>) -> Result<()> {
        let tx = self.conn.transaction()?;
        for change in changes {
            match change {
                IncomingChange::Upsert { record, modified } => {
                    tx.execute(
                        "INSERT INTO records (id, kind, payload, server_modified)
                         VALUES (?1, ?2, ?3, ?4)
                         ON CONFLICT(id) DO UPDATE SET
                            kind = excluded.kind,
                            payload = excluded.payload,
                            server_modified = excluded.server_modified",
                        params![
                            record.id,
                            record.kind,
                            serde_json::to_string(&record)?,
                            modified
                        ],
                    )?;
                }
                IncomingChange::Delete { id } => {
                    tx.execute("DELETE FROM records WHERE id = ?1", params![id])?;
                }
            }
        }
        tx.commit()?;
        Ok(())
    }

    pub fn all_records(&self) -> Result<Vec<SpacesRecord>> {
        let mut stmt = self
            .conn
            .prepare("SELECT payload FROM records ORDER BY id")?;
        let payloads = stmt
            .query_map([], |row| row.get::<_, String>(0))?
            .collect::<Result<Vec<_>, _>>()?;
        payloads
            .iter()
            .map(|p| Ok(serde_json::from_str(p)?))
            .collect()
    }

    pub fn wipe_records(&self) -> Result<()> {
        self.conn.execute("DELETE FROM records", [])?;
        Ok(())
    }

    pub fn get_meta(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row("SELECT value FROM meta WHERE key = ?1", params![key], |row| {
                row.get(0)
            })
            .optional()?)
    }

    pub fn put_meta(&self, key: &str, value: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO meta (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    pub fn delete_meta(&self, key: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM meta WHERE key = ?1", params![key])?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn record(id: &str, kind: &str) -> SpacesRecord {
        SpacesRecord {
            id: id.into(),
            kind: kind.into(),
            data: json!({}),
        }
    }

    #[test]
    fn upsert_replace_and_delete() {
        let mut storage = SpacesStorage::open_in_memory().unwrap();
        storage
            .apply_changes(vec![
                IncomingChange::Upsert {
                    record: record("a", "tab"),
                    modified: 1,
                },
                IncomingChange::Upsert {
                    record: record("b", "space"),
                    modified: 1,
                },
            ])
            .unwrap();
        storage
            .apply_changes(vec![
                IncomingChange::Upsert {
                    record: record("a", "folder"),
                    modified: 2,
                },
                IncomingChange::Delete { id: "b".into() },
            ])
            .unwrap();
        assert_eq!(storage.all_records().unwrap(), vec![record("a", "folder")]);
    }

    #[test]
    fn meta_round_trip() {
        let storage = SpacesStorage::open_in_memory().unwrap();
        assert_eq!(storage.get_meta("k").unwrap(), None);
        storage.put_meta("k", "1").unwrap();
        storage.put_meta("k", "2").unwrap();
        assert_eq!(storage.get_meta("k").unwrap().as_deref(), Some("2"));
        storage.delete_meta("k").unwrap();
        assert_eq!(storage.get_meta("k").unwrap(), None);
    }
}
