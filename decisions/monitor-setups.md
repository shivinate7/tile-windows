# Monitor setups

Kind: build
Plan: docs/design/mockups/monitor-setups-notes.md#monitor-setups (windows)

**Question.** How does the app know each monitor, group monitors into setups, keep a layout for each setup, and place windows when a monitor is unplugged? Item numbers below are the notes' own numbers.

**Ruling (owner, 2026-11-17 09:47 CST).**
- Item 9, where the missing ultrawide's windows go. The owner's own answer. The app remembers which windows were on the ultrawide, and their cells. While it is unplugged, those windows show in Windows That Stay Put as unplaced, so the owner can arrange a new layout for this setup. Windows That Stay Put lists the windows the board has not placed. When the ultrawide comes back, they return to their remembered cells. Owner's words: "windows that were on the ultrawide to be remembered that they were there but when unplugged and I'm on the app they should just be back in the dock as though they're unplaced so that way I can create a new arrangement".
  Departs from: main, `tile.ps1`'s per-role loop, which skips a role with no screen and lists its pins as missing.
- Item 7, follow or a frozen copy. Follow the closest known setup until the owner makes a change on the new one. Frozen copy: not taken. Replaces the mockup's pick.
- Item 17, the count triggers. Option a: replace the `monitors` extra ("For N screens") with "Use This Scene on This Setup", with a setup select. The `noext` extra ("Laptop only") stays. Keep both counts: not taken.
  Departs from: `decisions/triggers.md`, which picks a scene per monitor set. What was built counts screens (`app.html`, the `monitors` and `noext` extras).
- Item 8, autosave (owner, 2026-11-17 11:38 CST). Owner's word: "autosave". Every board edit is written straight away for the setup in use. Layouts have no Save or Revert. Undo still steps back moves. Replaces the mockup's pick. Loss: a test move is kept; Undo is the way back.
  Departs from: main, `app.html` `save` and `revert` buttons.

**Coordinator defaults, recorded 2026-11-17 09:50 CST.** The designer's picks the owner did not overrule. The notes mark items 1, 4, 5 and 14 "Owner grant: yes"; the owner's silence on them is not a grant.
- Item 1, how a monitor is known (coordinator default, owner may change). By its hardware: the maker, product code and serial Windows reports (`WmiMonitorID`), with the built-in screen found by its connection (`WmiMonitorConnectionParams`). Fallback: maker, product and port. Unmeasured: the builder verifies that a WMI monitor maps to a `Screen.DeviceName`, and how two identical monitors with no serial differ. Departs from: main, `tile.ps1` `Pick` and `Roles`, and `app.html` `ROLE` and `monName()`, which name a monitor by its size role.
- Item 4, what makes a new setup (coordinator default, owner may change). The sorted list of monitor IDs. Moving the same monitors, or changing their scale, is the same setup, and the board redraws at the new positions. "When the Monitors Change" does not fire on a rearrange. Departs from: main, `tray.ps1` `Get-MonitorKey`.
- Item 5, where a layout lives (coordinator default, owner may change). Each setup keeps its own grids, pins, zones, held cells and fill screen, keyed by monitor ID. Needs a `scenes.json` migration. Departs from: main, `scenes.json`, which names roles (`wide`, `tall`, `laptop`).
- Item 14, the first setup (coordinator default, owner may change). Seeded by shape: the `wide` grid to a monitor wider than 2:1, `tall` to one taller than wide, `laptop` to the built-in screen. A first launch with the ultrawide unplugged gives the laptop its own grid, and the `wide` part's windows show as unplaced.
- Edit only the plugged-in setup (coordinator default, owner may change). Monitors and Setups (item 13) is a dialog from the strip; a setup not plugged in cannot be edited. The rail option is not taken. This answers the critique's question on editing an unplugged setup.
- Item 7, closest known setup (coordinator default 2026-11-17 11:47 CST, owner may change): the known setup sharing the most monitors. A tie goes to the one used last. This is item 6's pick, and it is what "closest known setup" means.
- Edited mark (coordinator default 2026-11-17 11:47 CST, owner may change): a scene card shows `follows <setup>` while it follows, and `own layout` once any edit lands on this setup. Autosave makes the first edit the switch. This replaces the mockup's Edited mark and its tag.
- Follow again (coordinator default 2026-11-17 11:47 CST, owner may change): `Follow <setup> Again` stays, on the scene card's menu.
- Built-in scenes (coordinator default 2026-11-17 11:47 CST, owner may change): built-in scenes keep their own layout per setup, like any scene (item 5).
- Save (coordinator default 2026-11-17 11:47 CST, owner may change): Save stays for a scene's name and triggers only. Layouts autosave.
- Windows That Stay Put (coordinator default 2026-11-17 11:47 CST, owner may change): kept per setup, as part of the layout (item 5).
- Unplaced reason (coordinator default 2026-11-17 11:47 CST, owner may change): the reason text for an unplaced window is "Its screen is unplugged" (item 9).
- Offline page (coordinator default 2026-11-17 11:47 CST, owner may change): the offline page (`file://`) cannot autosave. Its edits stay in the page, and Apply downloads a place file, as today (item 8).
- Ultrawide (coordinator default 2026-11-17 11:47 CST, owner may change): for the grid trigger, an ultrawide is a monitor wider than 2:1, the item 14 shape rule.
- Item 10, fold select (coordinator default 2026-11-17 11:47 CST, owner may change): dropped. It follows from item 9's ruling, which folds nothing.

**Open, not ruled.**
- Item 7: the `Follow <setup> Again` control (`cd-own`) stays (coordinator default 2026-11-17 11:47 CST). What it links to is not ruled. The notes' items 11 and 16 still name Desk in their examples; rewording them is not ruled.
- Item 16, the scene card's words against its icon: the default has the card show `follows <setup>` and `own layout`, while the icon pick keeps the word in the mark's title and label. Whether the card shows the words is not ruled.

**Why.** The owner's ask, 2026-11-16 14:46 CST: "just like how windows remembers monitors and their layouts depending on whats plugged in cant we store that in memory too but act more dynamically than that". The item 9 answer lets the owner make a new arrangement while the ultrawide is unplugged.
