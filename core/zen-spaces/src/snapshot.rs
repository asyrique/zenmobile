/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

//! Resolves the flat record set into what a sidebar UI needs: spaces in the
//! user's order, each with an outline of folders, splits and tabs, plus the
//! Essentials per container.
//!
//! Trees are flattened into rows with a depth so the FFI types stay
//! non-recursive and a mobile list can render them directly.
//!
//! Records arrive one by one and may be inconsistent mid-sync (a space
//! listing a tab that hasn't arrived, a tab pointing at a deleted folder),
//! so resolution is forgiving: dangling ids are skipped, and items that
//! claim a parent which doesn't list them are appended to that parent
//! rather than lost.

use crate::record::{
    ContainerData, FolderData, LayoutData, RecordKind, SpaceData, SpacesRecord, SplitData,
    TabData, DEFAULT_ESSENTIALS_KEY,
};
use error_support::warn;
use std::collections::{BTreeMap, HashMap, HashSet};

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ZenSpacesSnapshot {
    pub spaces: Vec<ZenSpace>,
    pub essentials: Vec<ZenEssentials>,
    pub containers: Vec<ZenContainer>,
    /// Server time of the last successful sync of this collection, in
    /// milliseconds. `None` if the collection has never synced, which
    /// usually means desktop doesn't have Spaces sync enabled.
    pub last_sync_millis: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ZenContainer {
    pub guid: String,
    pub name: String,
    /// A Firefox container icon name (`fingerprint`, `briefcase`, ...).
    pub icon: String,
    /// A Firefox container color name (`blue`, `turquoise`, ...).
    pub color: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ZenSpace {
    pub uuid: String,
    pub name: String,
    pub icon: Option<String>,
    pub theme: Option<ZenSpaceTheme>,
    pub container: Option<ZenContainer>,
    pub rows: Vec<ZenSidebarRow>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ZenSpaceTheme {
    pub colors: Vec<ZenThemeColor>,
    pub opacity: f64,
    pub texture: f64,
    /// The theme exactly as desktop sent it, for anything not modelled here.
    pub raw_json: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ZenThemeColor {
    pub red: u8,
    pub green: u8,
    pub blue: u8,
    pub is_primary: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ZenSidebarRow {
    /// 0 for direct children of the space, +1 per enclosing folder.
    pub depth: u32,
    pub parent_folder_id: Option<String>,
    pub item: ZenSidebarItem,
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum ZenSidebarItem {
    Tab { tab: ZenTab },
    Folder { folder: ZenFolder },
    Split { split: ZenSplit },
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ZenTab {
    pub id: String,
    pub url: String,
    /// The user's custom label if they renamed the tab, else the page title,
    /// else the URL.
    pub title: String,
    pub icon: Option<String>,
    pub container: Option<ZenContainer>,
    pub pinned: bool,
    pub essential: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ZenFolder {
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub is_live: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ZenSplit {
    pub id: String,
    /// `grid`, `vsep` or `hsep`.
    pub layout: String,
    pub tabs: Vec<ZenTab>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ZenEssentials {
    /// `None` for Essentials outside any container.
    pub container: Option<ZenContainer>,
    pub tabs: Vec<ZenTab>,
}

#[derive(Default)]
struct Index {
    containers: HashMap<String, ContainerData>,
    spaces: HashMap<String, SpaceData>,
    tabs: HashMap<String, TabData>,
    folders: HashMap<String, FolderData>,
    splits: HashMap<String, SplitData>,
    layout: Option<LayoutData>,
}

impl Index {
    fn new(records: &[SpacesRecord]) -> Self {
        let mut index = Index::default();
        for record in records {
            match record.parse() {
                Ok(RecordKind::Container(c)) => {
                    index.containers.insert(record.id.clone(), c);
                }
                Ok(RecordKind::Space(s)) => {
                    index.spaces.insert(record.id.clone(), s);
                }
                Ok(RecordKind::Tab(t)) => {
                    index.tabs.insert(record.id.clone(), t);
                }
                Ok(RecordKind::Folder(f)) => {
                    index.folders.insert(record.id.clone(), f);
                }
                Ok(RecordKind::Split(s)) => {
                    index.splits.insert(record.id.clone(), s);
                }
                Ok(RecordKind::Layout(l)) => index.layout = Some(l),
                Ok(RecordKind::Unknown) => {}
                Err(e) => warn!("Skipping malformed {} record: {}", record.kind, e),
            }
        }
        index
    }

    fn container(&self, guid: Option<&str>) -> Option<ZenContainer> {
        let guid = guid?;
        let c = self.containers.get(guid)?;
        Some(ZenContainer {
            guid: guid.to_string(),
            name: c.name.clone(),
            icon: c.icon.clone(),
            color: c.color.clone(),
        })
    }

    fn tab(&self, id: &str) -> Option<ZenTab> {
        let t = self.tabs.get(id)?;
        let title = [t.static_label.as_deref().unwrap_or(""), &t.title, &t.url]
            .into_iter()
            .find(|s| !s.is_empty())
            .unwrap_or_default()
            .to_string();
        Some(ZenTab {
            id: id.to_string(),
            url: t.url.clone(),
            title,
            icon: non_empty(&t.icon),
            container: self.container(t.container_guid.as_deref()),
            pinned: t.pinned,
            essential: t.essential,
        })
    }
}

fn non_empty(s: &str) -> Option<String> {
    (!s.is_empty()).then(|| s.to_string())
}

/// Walks a space's outline. `visited` makes every item appear at most once
/// and stops folder cycles.
struct Outline<'a> {
    index: &'a Index,
    space: &'a str,
    visited: HashSet<String>,
    rows: Vec<ZenSidebarRow>,
}

impl Outline<'_> {
    fn emit(&mut self, id: &str, depth: u32, parent: Option<&str>) {
        if self.visited.contains(id) {
            return;
        }
        let item = if let Some(tab) = self.index.tab(id) {
            if tab.essential {
                return;
            }
            ZenSidebarItem::Tab { tab }
        } else if let Some(folder) = self.index.folders.get(id) {
            ZenSidebarItem::Folder {
                folder: ZenFolder {
                    id: id.to_string(),
                    name: folder.name.clone(),
                    icon: folder.icon.clone(),
                    is_live: folder.live.is_some(),
                },
            }
        } else if let Some(split) = self.index.splits.get(id) {
            let tabs: Vec<ZenTab> = split.tabs.iter().filter_map(|t| self.index.tab(t)).collect();
            if tabs.is_empty() {
                return;
            }
            for tab in &tabs {
                self.visited.insert(tab.id.clone());
            }
            ZenSidebarItem::Split {
                split: ZenSplit {
                    id: id.to_string(),
                    layout: split.grid_type.clone(),
                    tabs,
                },
            }
        } else {
            // Not arrived yet, or deleted; the next sync will settle it.
            return;
        };
        self.visited.insert(id.to_string());
        let is_folder = matches!(item, ZenSidebarItem::Folder { .. });
        self.rows.push(ZenSidebarRow {
            depth,
            parent_folder_id: parent.map(str::to_string),
            item,
        });
        if is_folder {
            self.emit_folder_children(id, depth + 1);
        }
    }

    fn emit_folder_children(&mut self, folder_id: &str, depth: u32) {
        let folder = &self.index.folders[folder_id];
        for child in &folder.children {
            self.emit(child, depth, Some(folder_id));
        }
        for id in self.orphans(Some(folder_id)) {
            self.emit(&id, depth, Some(folder_id));
        }
    }

    /// Items that name `folder` (or, for `None`, this space directly) as
    /// their parent but which the parent's `children` didn't list.
    fn orphans(&self, folder: Option<&str>) -> Vec<String> {
        let index = self.index;
        let in_space = |ws: &Option<String>| ws.as_deref() == Some(self.space);
        let mut ids: Vec<String> = Vec::new();
        for (id, f) in &index.folders {
            let parent = f
                .parent_folder_id
                .as_deref()
                .filter(|p| index.folders.contains_key(*p));
            if parent == folder && (folder.is_some() || in_space(&f.workspace_uuid)) {
                ids.push(id.clone());
            }
        }
        for (id, s) in &index.splits {
            let parent = s.folder_id.as_deref().filter(|p| index.folders.contains_key(*p));
            if parent == folder && (folder.is_some() || in_space(&s.workspace_uuid)) {
                ids.push(id.clone());
            }
        }
        for (id, t) in &index.tabs {
            let parent = t.folder_id.as_deref().filter(|p| index.folders.contains_key(*p));
            if !t.essential && parent == folder && (folder.is_some() || in_space(&t.workspace_uuid))
            {
                ids.push(id.clone());
            }
        }
        ids.retain(|id| !self.visited.contains(id));
        ids.sort();
        ids
    }
}

fn theme(value: &serde_json::Value) -> Option<ZenSpaceTheme> {
    if value.is_null() {
        return None;
    }
    let channel = |v: &serde_json::Value| v.as_f64().map(|n| n.round().clamp(0.0, 255.0) as u8);
    let colors = value
        .get("gradientColors")
        .and_then(|c| c.as_array())
        .map(|colors| {
            colors
                .iter()
                .filter_map(|color| {
                    let rgb = color.get("c")?.as_array()?;
                    Some(ZenThemeColor {
                        red: channel(rgb.first()?)?,
                        green: channel(rgb.get(1)?)?,
                        blue: channel(rgb.get(2)?)?,
                        is_primary: color
                            .get("isPrimary")
                            .and_then(|p| p.as_bool())
                            .unwrap_or(false),
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    Some(ZenSpaceTheme {
        colors,
        opacity: value.get("opacity").and_then(|v| v.as_f64()).unwrap_or(0.5),
        texture: value.get("texture").and_then(|v| v.as_f64()).unwrap_or(0.0),
        raw_json: value.to_string(),
    })
}

pub(crate) fn build_snapshot(
    records: &[SpacesRecord],
    last_sync_millis: Option<i64>,
) -> ZenSpacesSnapshot {
    let index = Index::new(records);
    let layout = index.layout.clone().unwrap_or_default();

    let mut space_order: Vec<&str> = layout
        .spaces
        .iter()
        .map(String::as_str)
        .filter(|uuid| index.spaces.contains_key(*uuid))
        .collect();
    let mut unlisted: Vec<&SpaceData> = index
        .spaces
        .iter()
        .filter(|(uuid, _)| !layout.spaces.contains(uuid))
        .map(|(_, s)| s)
        .collect();
    unlisted.sort_by(|a, b| a.name.cmp(&b.name).then(a.uuid.cmp(&b.uuid)));
    space_order.extend(unlisted.iter().map(|s| s.uuid.as_str()));
    space_order.dedup();

    let spaces = space_order
        .into_iter()
        .map(|uuid| {
            let space = &index.spaces[uuid];
            let mut outline = Outline {
                index: &index,
                space: uuid,
                visited: HashSet::new(),
                rows: Vec::new(),
            };
            for child in &space.children {
                outline.emit(child, 0, None);
            }
            for id in outline.orphans(None) {
                outline.emit(&id, 0, None);
            }
            ZenSpace {
                uuid: uuid.to_string(),
                name: space.name.clone(),
                icon: space.icon.clone().filter(|i| !i.is_empty()),
                theme: space.theme.as_ref().and_then(theme),
                container: index.container(space.container_guid.as_deref()),
                rows: outline.rows,
            }
        })
        .collect();

    ZenSpacesSnapshot {
        spaces,
        essentials: essentials(&index, &layout),
        containers: {
            let mut containers: Vec<ZenContainer> = index
                .containers
                .keys()
                .filter_map(|guid| index.container(Some(guid)))
                .collect();
            containers.sort_by(|a, b| a.name.cmp(&b.name).then(a.guid.cmp(&b.guid)));
            containers
        },
        last_sync_millis,
    }
}

fn essentials(index: &Index, layout: &LayoutData) -> Vec<ZenEssentials> {
    // Group key: container guid, or DEFAULT_ESSENTIALS_KEY.
    let mut groups: BTreeMap<String, Vec<String>> = layout.essentials.clone();
    let listed: HashSet<&String> = layout.essentials.values().flatten().collect();
    let mut unlisted: Vec<(&String, &TabData)> = index
        .tabs
        .iter()
        .filter(|(id, t)| t.essential && !listed.contains(id))
        .collect();
    unlisted.sort_by_key(|(id, _)| *id);
    for (id, tab) in unlisted {
        let key = tab
            .container_guid
            .clone()
            .unwrap_or_else(|| DEFAULT_ESSENTIALS_KEY.to_string());
        groups.entry(key).or_default().push(id.clone());
    }

    let mut result: Vec<ZenEssentials> = groups
        .into_iter()
        .filter_map(|(key, ids)| {
            let mut seen = HashSet::new();
            let tabs: Vec<ZenTab> = ids
                .iter()
                .filter(|id| seen.insert(*id))
                .filter_map(|id| index.tab(id))
                .collect();
            if tabs.is_empty() {
                return None;
            }
            let container = if key == DEFAULT_ESSENTIALS_KEY {
                None
            } else {
                index.container(Some(&key))
            };
            Some(ZenEssentials { container, tabs })
        })
        .collect();
    // No-container Essentials first, then by container name.
    result.sort_by(|a, b| match (&a.container, &b.container) {
        (None, None) => std::cmp::Ordering::Equal,
        (None, Some(_)) => std::cmp::Ordering::Less,
        (Some(_), None) => std::cmp::Ordering::Greater,
        (Some(x), Some(y)) => x.name.cmp(&y.name).then(x.guid.cmp(&y.guid)),
    });
    result
}

#[cfg(test)]
mod tests;
