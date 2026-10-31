/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/// Internal error type.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("SQL error: {0}")]
    Sql(#[from] rusqlite::Error),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

pub type Result<T, E = Error> = std::result::Result<T, E>;

/// Error exposed over the FFI.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ZenSpacesError {
    #[error("Storage error: {reason}")]
    Storage { reason: String },
}

impl From<Error> for ZenSpacesError {
    fn from(e: Error) -> Self {
        ZenSpacesError::Storage {
            reason: e.to_string(),
        }
    }
}
