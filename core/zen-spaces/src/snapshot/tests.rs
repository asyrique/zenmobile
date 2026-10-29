/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

use super::*;
use serde_json::{json, Value};

fn rec(id: &str, kind: &str, data: Value) -> SpacesRecord {
    SpacesRecord {
        id: id.into(),
        kind: kind.into(),
        data,
    }
}

fn tab(id: &str, url: &str, extra: Value) -> SpacesRecord {
    let mut data = json!({
        "tabId": id, "url": url, "title": id, "icon": "",
        "containerGuid": null, "essential": false, "pinned": true,
        "workspaceUuid": null, "folderId": null, "staticLabel": null,
        "hasStaticIcon": false, "defaultContainer": false
    });
    data.as_object_mut()
        .unwrap()
        .extend(extra.as_object().unwrap().clone());
    rec(id, "tab", data)
}

fn row_ids(space: &ZenSpace) -> Vec<(u32, String)> {
    space
        .rows
        .iter()
        .map(|row| {
            let id = match &row.item {
                ZenSidebarItem::Tab { tab } => tab.id.clone(),
                ZenSidebarItem::Folder { folder } => folder.id.clone(),
                ZenSidebarItem::Split { split } => split.id.clone(),
            };
            (row.depth, id)
        })
        .collect()
}

/// Mirrors what desktop's projections produce for a small but complete
/// profile: two spaces, a nested folder, a split, a container and Essentials.
fn desktop_fixture() -> Vec<SpacesRecord> {
    vec![
        rec("builtin-1", "container", json!({"guid": "builtin-1", "name": "Personal", "icon": "fingerprint", "color": "blue"})),
        rec("work-guid", "container", json!({"guid": "work-guid", "name": "Work", "icon": "briefcase", "color": "orange"})),
        rec("{work}", "space", json!({
            "uuid": "{work}", "name": "Work", "icon": "💼",
            "theme": {"type": "gradient", "gradientColors": [{"c": [120, 60, 200], "isPrimary": true}, {"c": [40, 20, 90]}], "opacity": 0.7, "texture": 0.1},
            "containerGuid": "work-guid",
            "children": ["f-banks", "t-gh", "split-1"]
        })),
        rec("{home}", "space", json!({"uuid": "{home}", "name": "Home", "icon": null, "theme": null, "containerGuid": null, "children": ["t-news"]})),
        rec("f-banks", "folder", json!({"folderId": "f-banks", "name": "Banks", "icon": null, "workspaceUuid": "{work}", "parentFolderId": null, "live": null, "children": ["t-bank", "f-cards"]})),
        rec("f-cards", "folder", json!({"folderId": "f-cards", "name": "Cards", "icon": null, "workspaceUuid": "{work}", "parentFolderId": "f-banks", "live": null, "children": ["t-card"]})),
        tab("t-bank", "https://bank.example/", json!({"workspaceUuid": "{work}", "folderId": "f-banks"})),
        tab("t-card", "https://card.example/", json!({"workspaceUuid": "{work}", "folderId": "f-cards", "staticLabel": "My card"})),
        tab("t-gh", "https://github.com/", json!({"workspaceUuid": "{work}"})),
        rec("split-1", "split", json!({"splitId": "split-1", "gridType": "vsep", "pinned": true, "tabs": ["t-docs", "t-mail"], "workspaceUuid": "{work}", "folderId": null})),
        tab("t-docs", "https://docs.example/", json!({"workspaceUuid": "{work}"})),
        tab("t-mail", "https://mail.example/", json!({"workspaceUuid": "{work}"})),
        tab("t-news", "https://news.example/", json!({"workspaceUuid": "{home}", "pinned": false})),
        tab("e-1", "https://calendar.example/", json!({"essential": true})),
        tab("e-2", "https://chat.example/", json!({"essential": true, "containerGuid": "work-guid"})),
        rec("layout", "layout", json!({"spaces": ["{work}", "{home}"], "essentials": {"default": ["e-1"], "work-guid": ["e-2"]}})),
    ]
}

#[test]
fn resolves_desktop_layout() {
    let snap = build_snapshot(&desktop_fixture(), Some(42));
    assert_eq!(snap.last_sync_millis, Some(42));
    assert_eq!(
        snap.spaces.iter().map(|s| s.name.as_str()).collect::<Vec<_>>(),
        vec!["Work", "Home"]
    );

    let work = &snap.spaces[0];
    assert_eq!(work.icon.as_deref(), Some("💼"));
    assert_eq!(work.container.as_ref().unwrap().name, "Work");
    assert_eq!(
        row_ids(work),
        vec![
            (0, "f-banks".into()),
            (1, "t-bank".into()),
            (1, "f-cards".into()),
            (2, "t-card".into()),
            (0, "t-gh".into()),
            (0, "split-1".into()),
        ]
    );
    assert_eq!(work.rows[3].parent_folder_id.as_deref(), Some("f-cards"));
    match &work.rows[3].item {
        ZenSidebarItem::Tab { tab } => assert_eq!(tab.title, "My card"),
        other => panic!("unexpected {other:?}"),
    }
    match &work.rows[5].item {
        ZenSidebarItem::Split { split } => {
            assert_eq!(split.layout, "vsep");
            assert_eq!(
                split.tabs.iter().map(|t| t.id.as_str()).collect::<Vec<_>>(),
                vec!["t-docs", "t-mail"]
            );
        }
        other => panic!("unexpected {other:?}"),
    }

    let theme = work.theme.as_ref().unwrap();
    assert_eq!(theme.colors.len(), 2);
    assert_eq!((theme.colors[0].red, theme.colors[0].green, theme.colors[0].blue), (120, 60, 200));
    assert!(theme.colors[0].is_primary);
    assert_eq!(theme.opacity, 0.7);

    let home = &snap.spaces[1];
    assert!(home.theme.is_none());
    assert_eq!(row_ids(home), vec![(0, "t-news".into())]);

    assert_eq!(snap.essentials.len(), 2);
    assert!(snap.essentials[0].container.is_none());
    assert_eq!(snap.essentials[0].tabs[0].url, "https://calendar.example/");
    assert_eq!(snap.essentials[1].container.as_ref().unwrap().guid, "work-guid");

    assert_eq!(
        snap.containers.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
        vec!["Personal", "Work"]
    );
}

#[test]
fn essentials_never_appear_inside_spaces() {
    let mut records = desktop_fixture();
    // A stale space listing that still names an Essential.
    records.push(rec("{x}", "space", json!({"uuid": "{x}", "name": "X", "children": ["e-1"]})));
    let snap = build_snapshot(&records, None);
    let x = snap.spaces.iter().find(|s| s.uuid == "{x}").unwrap();
    assert!(x.rows.is_empty());
}

#[test]
fn partial_sync_is_forgiving() {
    let records = vec![
        // Space lists a tab and folder that haven't arrived yet.
        rec("{s}", "space", json!({"uuid": "{s}", "name": "S", "children": ["missing-tab", "missing-folder", "t-1"]})),
        tab("t-1", "https://one.example/", json!({"workspaceUuid": "{s}"})),
        // Tab claims the space, but the space's children don't list it yet.
        tab("t-2", "https://two.example/", json!({"workspaceUuid": "{s}"})),
        // Tab in a folder that was deleted: lands at the space's top level.
        tab("t-3", "https://three.example/", json!({"workspaceUuid": "{s}", "folderId": "gone"})),
        // Space not in the (missing) layout record is still shown.
    ];
    let snap = build_snapshot(&records, None);
    assert_eq!(snap.spaces.len(), 1);
    assert_eq!(
        row_ids(&snap.spaces[0]),
        vec![(0, "t-1".into()), (0, "t-2".into()), (0, "t-3".into())]
    );
}

#[test]
fn folder_cycles_terminate() {
    let records = vec![
        rec("{s}", "space", json!({"uuid": "{s}", "name": "S", "children": ["a"]})),
        rec("a", "folder", json!({"folderId": "a", "name": "A", "workspaceUuid": "{s}", "parentFolderId": "b", "children": ["b"]})),
        rec("b", "folder", json!({"folderId": "b", "name": "B", "workspaceUuid": "{s}", "parentFolderId": "a", "children": ["a"]})),
    ];
    let snap = build_snapshot(&records, None);
    assert_eq!(row_ids(&snap.spaces[0]), vec![(0, "a".into()), (1, "b".into())]);
}

#[test]
fn split_members_are_not_repeated_as_tabs() {
    let records = vec![
        rec("{s}", "space", json!({"uuid": "{s}", "name": "S", "children": ["sp", "t-a"]})),
        rec("sp", "split", json!({"splitId": "sp", "gridType": "grid", "tabs": ["t-a", "t-b"], "workspaceUuid": "{s}"})),
        tab("t-a", "https://a.example/", json!({"workspaceUuid": "{s}"})),
        tab("t-b", "https://b.example/", json!({"workspaceUuid": "{s}"})),
    ];
    let snap = build_snapshot(&records, None);
    assert_eq!(row_ids(&snap.spaces[0]), vec![(0, "sp".into())]);
}

#[test]
fn malformed_records_are_skipped() {
    let records = vec![
        rec("{s}", "space", json!({"uuid": "{s}", "name": "S", "children": "not-a-list"})),
        rec("{t}", "space", json!({"uuid": "{t}", "name": "T"})),
    ];
    let snap = build_snapshot(&records, None);
    assert_eq!(snap.spaces.len(), 1);
    assert_eq!(snap.spaces[0].name, "T");
}
