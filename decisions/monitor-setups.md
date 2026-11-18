# Monitor setups

Kind: build
Plan: docs/design/mockups/monitor-setups-notes.md#monitor-setups (windows)

**Question.** How does the app know each monitor, group monitors into setups, keep a layout for each setup, and place windows when a monitor is unplugged? Item numbers below are the notes' own numbers.

**Ruling (owner, 2026-11-17 09:47 CST).**
- Item 9, where the missing ultrawide's windows go. The owner's own answer. The app remembers which windows were on the ultrawide, and their cells. While it is unplugged, those windows show in Windows That Stay Put as unplaced, so the owner can arrange a new layout for this setup. Windows That Stay Put lists the windows the board has not placed. When the ultrawide comes back, they return to their remembered cells. Owner's words: "windows that were on the ultrawide to be remembered that they were there but when unplugged and I'm on the app they should just be back in the dock as though they're unplaced so that way I can create a new arrangement".
  Departs from: main, `tile.ps1`'s per-role loop, which skips a role with no screen and lists its pins as missing.
- Item 7, follow or a frozen copy. Follow the closest known setup until the owner makes a change on the new one. Frozen copy: not taken. Replaces the mockup's pick.
- Item 17, the count triggers. Option a: replace the `monitors` extra ("For N screens") with "Use This Scene on This Setup", with a setup select. The `noext` extra ("Laptop only") stays. Keep both counts: not taken.
  Departs from: `decisions/triggers.md`, which picks a scene per monitor set. The `monitors` extra (a screen count) is replaced by the setup pick, built in PR 31 (setup-trigger, see Built).
- Item 8, autosave (owner, 2026-11-17 11:38 CST). Owner's word: "autosave". Every board edit is written straight away for the setup in use. Layouts have no Save or Revert. Undo still steps back moves. Replaces the mockup's pick. Loss: a test move is kept; Undo is the way back.
  Departs from: main, `app.html` `save` and `revert` buttons.

**Coordinator defaults, recorded 2026-11-17 09:50 CST.** The designer's picks the owner did not overrule. The notes mark items 1, 4, 5 and 14 "Owner grant: yes"; the owner's silence on them is not a grant.
- Item 1, how a monitor is known (coordinator default, owner may change). By its hardware: the maker, product code and serial Windows reports (`WmiMonitorID`), with the built-in screen found by its connection (`WmiMonitorConnectionParams`). Fallback, first match wins, in this order (`Get-MonitorIdentity`, `tile.ps1`): maker+product plus the EDID serial, text or number (`edid`); maker+product-`builtin` for the machine's own panel, when there is no serial (`builtin`); maker+product plus the port UID, when there is no serial (`port`); `size-WxH` only when Windows reports no device at all (`size`). Unmeasured: the builder verifies that a WMI monitor maps to a `Screen.DeviceName`, and how two identical monitors with no serial differ. Departs from: main, `tile.ps1` `Pick` and `Roles`, and `app.html` `ROLE` and `monName()`, which name a monitor by its size role.
- Item 4, what makes a new setup (coordinator default, owner may change). The sorted list of monitor IDs. Moving the same monitors, or changing their scale, is the same setup, and the board redraws at the new positions. "When the Monitors Change" does not fire on a rearrange. Departs from: main, `tray.ps1` `Get-MonitorKey`.
- Item 5, where a layout lives (coordinator default, owner may change). Each setup keeps its own grids, pins, zones, held cells and fill screen, keyed by monitor ID. Needs a `scenes.json` migration. Departs from: main, `scenes.json`, which names roles (`wide`, `tall`, `laptop`).
- Item 14, the first setup (coordinator default 2026-11-17 13:26 CST, owner may change; amended by coordinator rulings 17:27, 17:42 and 17:52 CST). Seeded by shape: `laptop` to the built-in screen; `wide` to the widest non-built-in landscape monitor (any aspect, 16:9 included); `tall` to a non-built-in monitor taller than wide. Each role goes to one monitor only: the widest candidate, then the lowest id. With two or more monitors a built-in screen never takes `wide`. A lone plugged monitor holds the `laptop` and `wide` roles, and `tall` too when it is portrait, as on main. `tile.ps1` `Pick` reads `Get-TileRoles` (`config.ps1`), the one home for this pick. Solo (the one-screen scene `solo` in `scenes.json`) keeps main's `wide` pins: Chrome on the `wide` screen. A zero width or height has no shape. Names: Laptop for the built-in screen; Ultrawide only when wider than 2:1; Portrait when taller than wide; otherwise "Monitor N". With two or more monitors plugged in, a first launch with the `wide` monitor unplugged gives the laptop its own grid, and the `wide` part's windows show as unplaced.
  Departs from: main `tile.ps1` `Pick`, with two or more monitors only: the widest screen takes `wide` even when it is the laptop. There the laptop never takes `wide`.
- Coordinator 19:03 CST: a direct `tile.ps1 -Proc` run with `-Monitor wide` (default or explicit) and no monitor holding the wide role falls back to the widest screen, as main did. Scenes and the role path keep item 14 (a wide pin with no wide monitor goes to `left`).
- Edit only the plugged-in setup (coordinator default, owner may change). Monitors and Setups (item 13) is a dialog from the strip; a setup not plugged in cannot have its layout edited. Its name can change either way (20:33 CST ruling). The rail option is not taken. This answers the critique's question on editing an unplugged setup.
- Item 7, closest known setup (coordinator default 2026-11-17 11:47 CST, owner may change): the known setup sharing the most monitors. A tie goes to the one used last. This is item 6's pick, and it is what "closest known setup" means.
- Edited mark (coordinator default 2026-11-17 11:47 CST, owner may change; the marks themselves are set by the 18:05 and 18:09 CST rulings below): autosave makes the first edit the switch.
- Follow again (coordinator default 2026-11-17 11:47 CST, owner may change): `Follow <setup> Again` stays, on the scene card's menu.
- Built-in scenes (coordinator default 2026-11-17 11:47 CST, owner may change): built-in scenes keep their own layout per setup, like any scene (item 5).
- Save (coordinator default 2026-11-17 11:47 CST, owner may change): Save stays for a scene's name and triggers only. Layouts autosave.
- Windows That Stay Put (coordinator default 2026-11-17 11:47 CST, owner may change): kept per setup, as part of the layout (item 5).
- Unplaced reason (coordinator default 2026-11-17 11:47 CST, owner may change): the reason text for an unplaced window is "Its screen is unplugged" (item 9).
- Offline page (coordinator default 2026-11-17 11:47 CST, owner may change): the offline page (`file://`) cannot autosave. Its edits stay in the page, and Apply downloads a place file, as today (item 8).
- Item 10, fold select (coordinator default 2026-11-17 11:47 CST, owner may change): dropped. It follows from item 9's ruling, which folds nothing.

**Coordinator rulings, 2026-11-17.**
- 13:28 CST: the grid trigger's "ultrawide" is whichever monitor holds the wide role.
- 15:19 CST: the engine never resolves the closest setup; the server posts the resolved layout.
- 15:23 CST: the tray keeps the name Get-MonitorKey but returns the setup key from monitor ids.
- 15:23 CST: a 404 "route absent" counts as red for a new route.
- 15:30 CST: windows the layout's fill would put on an unplugged monitor go to `left` as "Its screen is unplugged" (extends owner item 9).
- 17:35 CST: on the role path, a window pinned to a role no plugged monitor holds goes to `left` as "Its screen is unplugged", not `missing` (extends the 15:30 ruling and owner item 9, where an unplugged monitor's windows go).
- 16:18 CST: POST /config never writes layouts, for any key; only POST /layout does.
- 18:07 CST: a lone monitor holding several roles seeds its grid in the role order wide, tall, laptop (`Get-TileRoleOrder`, `config.ps1`, the one home).
- 18:05 CST: a save the server refuses after a setup change (409) shows an amber "setup changed" strip with Refresh, not Try Again.
- 18:05 CST: Apply or Refresh onto a new setup clears Undo.
- 18:05 CST, closed 19:46 CST: autosave keeps every Windows That Stay Put and held entry. Save writes only a scene's name and triggers (POST /config never writes layouts, 16:18 CST), so no Save drops them either.
- 18:05 CST: a failed GET /layouts or GET /config shows on the strip.
- 18:05 CST: card marks follow the mockup, and show only while some scene follows another setup.
- 18:05 CST: a monitor with no grid gets an "Add a Grid" button.
- 18:09 CST: a card mark is an icon beside Built-In, with a title and aria-label, and no visible words. This answers item 16.
- 18:28 CST: GET /layouts returns, per scene, {layout, follows, closest}. `follows` comes from `Get-TileFollows` and `closest` from `Get-TileClosestName` (`config.ps1`); both pick through `Get-TileClosestSetup`, the one home for the closest-setup pick.
- 20:26 CST: "Follow Desk Again" removes a scene's own layout for the current setup, through POST /layout/remove {scene,key}. It takes the /layout lock, re-reads config under it, answers 409 for a setup not plugged in and 404 for an unknown scene. A repeat is a no-op.
- 20:33 CST: the dialog's routes are POST /rename {kind,id,name} and POST /forget {kind,id}. Renaming any setup or monitor is allowed, plugged in or not, since a name is not a layout edit.
- 20:56 and 21:04 CST, narrowed 21:33 CST: Forget refuses only the setup in use. When the in-use key cannot be computed, it refuses any setup holding a plugged monitor. Forgetting a monitor also removes the setups holding it. Forgetting a setup turns off scene triggers aimed at it (flag off, setupKey cleared, a "pick a setup" note), on the server and on every page copy.
- Coordinator ruling, 2026-11-17, recorded 23:14 CST: the mockup's `bd-noid` state (a monitor with no ID) is dropped. No monitor lacks an ID. Each gets one in the order of item 1 (`Get-MonitorIdentity`, `tile.ps1`). The size (`size-WxH`) is used only when Windows reports no device at all. So no amber strip and no "Remember It by Its Size" button. Departs from: plan lane H and mockup `bd-noid`.

**Built.**
- Identity, PR 27 (monitor ids): built and merged.
- Config v4, PR 26 (setup config): built and merged.
- Engine, PR 28 (engine layouts): built and merged.
- Server and tray, PR 29 (setup plumbing): built and merged.
- Item 17, the count triggers, PR 31 (setup-trigger, open draft): built. "Use This Scene on This Setup" replaces the `monitors` extra ("For N screens"), with flag `setup` and `scene.setupKey`. The old `monitors` flag migrates off, with a note. The grid trigger uses the wide-role monitor by id.
- Item 8, autosave and the setup strip, PR 33 (board setups, open draft): built.
  Departs from: the mockup. An unplugged monitor is drawn dashed beside the plugged ones, since config keeps only its size.
- Item 7, Follow Desk Again, PR 35 (Follow Desk Again): built.
- Item 13, Monitors and Setups dialog, PR 36 (setups-dialog): built.

**Open, not ruled.**
- The notes' items 11 and 16 still name Desk in their examples; rewording them is not ruled.

**Why.** The owner's ask, 2026-11-16 14:46 CST: "just like how windows remembers monitors and their layouts depending on whats plugged in cant we store that in memory too but act more dynamically than that". The item 9 answer lets the owner make a new arrangement while the ultrawide is unplugged.
