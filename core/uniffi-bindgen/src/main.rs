/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

//! Bindings generator pinned to the same uniffi fork application-services
//! uses. Run in library mode against the built zen-core library:
//!
//!   cargo run -p uniffi-bindgen -- generate --library <libzen_core> --language swift --out-dir <dir>

fn main() -> anyhow::Result<()> {
    embedded_uniffi_bindgen::main()
}
