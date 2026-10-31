/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

//! Wire format of the `spaces` collection, mirroring the projections in
//! zen-browser/desktop `src/zen/sync/ZenSpacesSyncModel.sys.mjs`.
//!
//! Every field is defaulted: desktop omits nothing today, but a future
//! desktop may, and a missing field must never make us drop the record.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Key in [`LayoutData::essentials`] for tabs outside any container.
pub const DEFAULT_ESSENTIALS_KEY: &str = "default";

/// The decrypted cleartext of one BSO.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SpacesRecord {
    pub id: String,
    pub kind: String,
    #[serde(default)]
    pub data: serde_json::Value,
}

/// A parsed record. Unknown kinds (from a newer desktop) are kept as
/// [`RecordKind::Unknown`] so we can store them and ignore them in the UI.
#[derive(Debug, Clone, PartialEq)]
pub enum RecordKind {
    Container(ContainerData),
    Space(SpaceData),
    Tab(TabData),
    Folder(FolderData),
    Split(SplitData),
    Layout(LayoutData),
    Unknown,
}

impl SpacesRecord {
    pub fn parse(&self) -> serde_json::Result<RecordKind> {
        let data = self.data.clone();
        Ok(match self.kind.as_str() {
            "container" => RecordKind::Container(serde_json::from_value(data)?),
            "space" => RecordKind::Space(serde_json::from_value(data)?),
            "tab" => RecordKind::Tab(serde_json::from_value(data)?),
            "folder" => RecordKind::Folder(serde_json::from_value(data)?),
            "split" => RecordKind::Split(serde_json::from_value(data)?),
            "layout" => RecordKind::Layout(serde_json::from_value(data)?),
            _ => RecordKind::Unknown,
        })
    }
}

/// A Firefox container (contextual identity). Ids `builtin-1`..`builtin-4`
/// are the four containers every Firefox profile ships with.
/// Treats an explicit JSON `null` like a missing field.
fn nullable<'de, D, T>(deserializer: D) -> Result<T, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Default + Deserialize<'de>,
{
    Ok(Option::<T>::deserialize(deserializer)?.unwrap_or_default())
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ContainerData {
    #[serde(deserialize_with = "nullable")]
    pub guid: String,
    #[serde(deserialize_with = "nullable")]
    pub name: String,
    #[serde(deserialize_with = "nullable")]
    pub icon: String,
    #[serde(deserialize_with = "nullable")]
    pub color: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct SpaceData {
    #[serde(deserialize_with = "nullable")]
    pub uuid: String,
    #[serde(deserialize_with = "nullable")]
    pub name: String,
    /// An emoji, or a `chrome://` URL for one of Zen's built-in icons.
    pub icon: Option<String>,
    /// `{ type: "gradient", gradientColors: [{ c: [r, g, b], ... }], opacity, texture }`.
    pub theme: Option<serde_json::Value>,
    pub container_guid: Option<String>,
    /// Direct children in sidebar order: tab, folder and split ids.
    #[serde(deserialize_with = "nullable")]
    pub children: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct TabData {
    #[serde(deserialize_with = "nullable")]
    pub tab_id: String,
    /// For pinned tabs and Essentials this is the URL at pin time, not
    /// where the tab has navigated since.
    #[serde(deserialize_with = "nullable")]
    pub url: String,
    #[serde(deserialize_with = "nullable")]
    pub title: String,
    /// Only `data:`/`chrome:`/`about:`/`resource:` icons survive desktop's
    /// filter, so this is usually empty or a data URL.
    #[serde(deserialize_with = "nullable")]
    pub icon: String,
    pub container_guid: Option<String>,
    #[serde(deserialize_with = "nullable")]
    pub essential: bool,
    #[serde(deserialize_with = "nullable")]
    pub pinned: bool,
    /// `None` for Essentials, which live outside any space.
    pub workspace_uuid: Option<String>,
    pub folder_id: Option<String>,
    /// A label the user gave the tab, overriding the page title.
    pub static_label: Option<String>,
    #[serde(deserialize_with = "nullable")]
    pub has_static_icon: bool,
    #[serde(deserialize_with = "nullable")]
    pub default_container: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct FolderData {
    #[serde(deserialize_with = "nullable")]
    pub folder_id: String,
    #[serde(deserialize_with = "nullable")]
    pub name: String,
    pub icon: Option<String>,
    pub workspace_uuid: Option<String>,
    pub parent_folder_id: Option<String>,
    /// Live-folder provider config (RSS, GitHub, ...). Opaque to us.
    pub live: Option<serde_json::Value>,
    #[serde(deserialize_with = "nullable")]
    pub children: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct SplitData {
    #[serde(deserialize_with = "nullable")]
    pub split_id: String,
    /// `grid`, `vsep` or `hsep` on desktop.
    #[serde(deserialize_with = "nullable")]
    pub grid_type: String,
    #[serde(deserialize_with = "nullable")]
    pub pinned: bool,
    #[serde(deserialize_with = "nullable")]
    pub tabs: Vec<String>,
    pub workspace_uuid: Option<String>,
    pub folder_id: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct LayoutData {
    /// Space uuids in the order the user arranged them.
    #[serde(deserialize_with = "nullable")]
    pub spaces: Vec<String>,
    /// Essentials tab ids, keyed by container guid or [`DEFAULT_ESSENTIALS_KEY`].
    #[serde(deserialize_with = "nullable")]
    pub essentials: BTreeMap<String, Vec<String>>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_desktop_tab_record() {
        let record: SpacesRecord = serde_json::from_value(json!({
            "id": "tab-1",
            "kind": "tab",
            "data": {
                "tabId": "tab-1",
                "url": "https://example.com/",
                "title": "Example",
                "icon": "",
                "containerGuid": null,
                "essential": false,
                "pinned": true,
                "workspaceUuid": "{space-a}",
                "folderId": null,
                "staticLabel": null,
                "hasStaticIcon": false,
                "defaultContainer": false
            }
        }))
        .unwrap();
        match record.parse().unwrap() {
            RecordKind::Tab(tab) => {
                assert_eq!(tab.url, "https://example.com/");
                assert!(tab.pinned);
                assert_eq!(tab.workspace_uuid.as_deref(), Some("{space-a}"));
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn tolerates_missing_fields_and_unknown_kinds() {
        let record: SpacesRecord =
            serde_json::from_value(json!({"id": "s", "kind": "space", "data": {"uuid": "s"}}))
                .unwrap();
        assert!(matches!(record.parse().unwrap(), RecordKind::Space(s) if s.children.is_empty()));

        let record: SpacesRecord =
            serde_json::from_value(json!({"id": "x", "kind": "hologram", "data": {}})).unwrap();
        assert_eq!(record.parse().unwrap(), RecordKind::Unknown);

        let record: SpacesRecord = serde_json::from_value(
            json!({"id": "t", "kind": "tab", "data": {"tabId": "t", "title": null, "pinned": null}}),
        )
        .unwrap();
        assert!(matches!(record.parse().unwrap(), RecordKind::Tab(t) if t.title.is_empty() && !t.pinned));
    }
}
