# Zen Mobile — UX

Layout follows **Arc Search** on iOS; content and naming follow **Zen desktop**
(Spaces, Essentials, folders, Glance). The phone is a remote for your desktop
sidebar as much as a browser.

## Three surfaces

### 1. Browser (home)

Full-bleed web content. A single floating bottom bar, tinted by the current Space's
gradient:

```
┌──────────────────────────────┐
│                              │
│          web page            │
│                              │
│                     ┌──────┐ │  ← page actions pill (reader, share, …)
│                     └──────┘ │
├──────────────────────────────┤
│ [▣▣]        [ + ]        [^] │
└──────────────────────────────┘
   tabs      new tab      Space sheet
```

- **Tabs** (left): stacked thumbnail of open tabs → opens the carousel.
- **+** (center): new tab, focused address field. Long-press: new tab in another Space.
- **^** (right): opens the Space sheet. Swipe up on the bar does the same.
- Bar hides on scroll down and returns on scroll up or at page end, as in Arc Search.
- Swipe left/right on the bar switches between tabs in the current Space.

### 2. Tab carousel

Horizontally paged cards, each with favicon + title above it (Arc Search's switcher).
Swipe a card up to close. Bottom row:

```
 [🖥]            [  +  ]            [⚙]
desktop tabs     new tab          settings
```

- **🖥 Desktop tabs**: Firefox Sync's `tabs` collection. A list grouped by device
  (and, if the device sent them, by window and tab group). Tap to open here.
  Swipe a row to close it on that device (FxA close-tabs command).

### 3. Space sheet

A full-height card over the browser, Arc Search's "Spaces" screen, filled with Zen's
data from `ZenSpacesSnapshot`:

```
╭──────────────────────────────╮  background: the Space's theme gradient
│ Work                      ⊗  │  ← Space name, close
│                              │
│ ◼◼◼◼  Essentials (grid)      │  ← favicon tiles, per container
│                              │
│ 📁 Banks                     │  ← folders expand inline
│ 📁 AI Stuff                  │
│ 📁 Pull Requests  (live)     │  ← live folder badge
│ ▢ GitHub                     │  ← pinned tab
│ ▥ Docs | Mail                │  ← split view, opens as two tabs
│ ────────────                 │
│ ○ normal tabs (if synced)    │
├──────────────────────────────┤
│ 💼  •  🙂  💩  •  🪝  ⚡  🤐  │  ← Spaces bar: icons, swipe to switch
╰──────────────────────────────╯
```

- **Spaces bar** along the bottom: one icon per Space, in desktop's order, with the
  current one highlighted. Spaces without an icon show a dot. Swipe the sheet
  horizontally to change Space; the gradient cross-fades.
- **Essentials** across the top as a grid of favicon tiles (Zen desktop shows them
  as tiles above the sidebar).
- **Rows** come straight from `ZenSpace.rows`; `depth` is the indent.
- Tapping a pinned tab or Essential opens it **in this phone's tab for that item**
  (one phone tab per desktop pin, like Zen's pinned-tab reset behaviour), not a new tab
  every time.
- If `last_sync_millis` is `None`: an empty state explaining how to turn on Spaces sync
  on desktop (Twilight, or `services.sync.engine.spaces` = true).

## Visual language

- Space theme → `ZenSpaceTheme.colors` as a linear gradient at `opacity`, with
  a subtle grain overlay when `texture > 0`.
- System font, large bold titles (as in the Arc screenshots), rounded 24–32 pt
  corner radii, translucent materials over the gradient.
- Dark by default; light follows the system.
- Favicons: `ZenTab.icon` when it's a `data:` URL, otherwise fetched and cached locally.

## Out of scope (for now)

- Editing Spaces on mobile (the sync engine is read-only; see ARCHITECTURE.md).
- Arc Search's "Browse for me" AI summaries.
- Split view on phones. A split opens its first tab, with the rest a swipe away.
