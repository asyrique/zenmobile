/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

//! Client for the `spaces` collection that Zen Browser desktop writes to
//! Firefox Sync (see `src/zen/sync/ZenSpacesSync*.sys.mjs` in
//! zen-browser/desktop).
//!
//! The collection holds one record per synced object, each with a cleartext
//! of `{ id, kind, data }`. Kinds are `container`, `space`, `tab`, `folder`,
//! `split` and a singleton `layout` record that orders the spaces and lists
//! the Essentials per container.
//!
//! This crate is deliberately **read-only**: the engine never uploads. The
//! desktop applier reconciles incoming records straight into the live
//! browser, so a buggy writer here would rearrange (or delete) people's
//! sidebars on every desktop they own. Writing comes later, once the
//! read path has been proven against real data.

mod engine;
mod error;
mod record;
mod snapshot;
mod storage;
mod store;

pub use engine::ZenSpacesEngine;
pub use error::{Error, Result, ZenSpacesError};
pub use record::{RecordKind, SpacesRecord};
pub use snapshot::{
    ZenContainer, ZenEssentials, ZenFolder, ZenSidebarItem, ZenSidebarRow, ZenSpace,
    ZenSpaceTheme, ZenSpacesSnapshot, ZenSplit, ZenTab, ZenThemeColor,
};
pub use store::ZenSpacesStore;

/// The collection name Zen desktop registers its engine under
/// (`SyncEngine("Spaces")` lower-cases to this).
pub const COLLECTION_NAME: &str = "spaces";

/// The engine version of Zen desktop this crate's record model was written
/// against (`ZenSpacesSyncEngine.version`). sync15 does not hand engines the
/// `meta/global` version, so this is documentation, not enforcement: the
/// parser instead tolerates missing fields and skips unknown kinds.
pub const MODELLED_ENGINE_VERSION: usize = 3;

uniffi::setup_scaffolding!("zen_spaces");
