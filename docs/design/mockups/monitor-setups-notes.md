# Monitor setups: design notes

Mockup: `monitor-setups.html`, beside this file. Owner's ask, 2026-11-16 14:46 CST: "just like how
windows remembers monitors and their layouts depending on whats plugged in cant we store that in
memory too but act more dynamically than that". Designer kind: informed.

Deep links: `#s=<state>`, plus `w=1024`, `t=light|dark`, `labels=0` and `hide=<option,...>`. With
no `t`, the page follows the system theme. `#s=all` shows every state.
States: `bd-today`, `bd-new`, `bd-back`, `bd-noid`, `fd-laptop`, `fd-portrait`, `fd-stay`,
`mg-dialog`, `mg-first`, `mg-rail`, `cd-follow`, `cd-own`, `cd-word`.
Option keys for `hide`: `setups`, `laptop`, `portrait`, `stay`, `dialog`, `rail`, `icon`, `word`.

Sizes: 1440 and 1024, light and dark, the brief's sizes; `layout.py devices` gives no device list
for this repo. Tokens and app CSS are copied from `stack-tweaks.html`, which copies `app.html`. No
web fonts, so the page opens with no network.

Focus ids for the waiting page, each prefixed by its state key: `-setbar` (bd-new, bd-back,
bd-noid, fd-stay, cd-own), `-target` (fd-laptop, fd-portrait), `-list` (fd-stay), `-dlg`
(mg-dialog), `-setups` (mg-first, mg-rail), `-cards` (cd-follow, cd-word), `-card` (cd-own).

Terms. A **setup** is the set of monitors plugged in at once. A scene's layout on a setup either
**follows** another setup (built from it, and kept in step with it) or is its **own layout**
(changed on that setup). "Follows Desk" is the one phrase the screen uses for the first.

Unchanged from main: the board, tiles, stacks, the inspector's Columns and Rows, and the "When the Monitors Change" trigger,
which applies its scene on a setup change as today (`decisions/triggers.md`). A setup change
redraws the board; windows move on Apply or by that trigger, as today. Windows That Stay Put is kept per setup (item 5).

## 1. Know each monitor by its hardware

1. **Identity.** Options: hardware ID (pick), the maker, product code and serial Windows reports
   (`WmiMonitorID`), with the built-in screen found by its connection
   (`WmiMonitorConnectionParams`); or today's size rank.
   Gain: the laptop stays "Laptop" with the ultrawide gone (`bd-new` against `bd-today`), and a
   different 27-inch at home is its own monitor. Loss: a new data home, and a WMI read on each
   monitor change.
   Unmeasured; the builder verifies: that a WMI monitor maps to a `Screen.DeviceName`, and how two
   identical monitors with no serial differ. Fallback: maker + product + the port.
   Departs from: main, `tile.ps1` `Pick` and `Roles` (about lines 127-138), which give the widest
   screen the `wide` role, the tallest `tall` and the smallest `laptop`; and `app.html` `ROLE` and
   `monName()`, which name a screen by that role. Owner grant: yes.
2. **Names.** Options: named by shape at first sight (pick): Laptop (built-in), Ultrawide (wider
   than 2:1), Portrait (taller than wide), else "Monitor N"; or Windows' model name.
   Gain: the owner's three names stay, so nothing reads new on day one. Loss: a second same-shape
   monitor reads "Monitor N" until renamed. The owner renames in the inspector's Monitor section
   (`Name`, every state but `bd-today`) or in Monitors and Setups.
3. **A monitor with no ID** (`bd-noid`). Options: say so and offer Remember It by Its Size
   (pick); or remember it by size with no question. The strip turns amber; the scene follows the
   closest setup, and changes last until it is unplugged.
   Gain: the owner knows why it will not be remembered, and one control leads on. Loss of the other
   option: two hotel monitors of one size become one monitor.

## 2. Setups and their layouts

4. **What makes a new setup.** Options: the sorted list of monitor IDs (pick); or today's key of
   device name, size and position. Under the pick, moving the same monitors or changing their
   scale is the same setup, and the board redraws at the new positions.
   Gain: a rearrange or a scale change keeps every layout. Loss: "When the Monitors Change" no
   longer fires on a rearrange of the same monitors.
   Departs from: main, `tray.ps1` `Get-MonitorKey` (line 25). Owner grant: yes.
5. **Where a layout lives.** Each scene keeps grids, pins, zones, held cells and the fill screen
   per setup, keyed by monitor ID. Gain: a setup's layout never changes another's. Loss: a bigger
   `scenes.json` and a migration. Pick: per setup. Coordinator default 2026-11-17 11:47 CST, owner may
   change: Windows That Stay Put is kept per setup, as part of the layout, and built-in scenes keep
   their own layout per setup like any scene.
   Departs from: main, `scenes.json`, where each scene's `grids`, `pins[].mon`, `zones[].mon`,
   `fill.mon` and `fill.held[].mon` name a role (`wide`, `tall`, `laptop`). Owner grant: yes.
6. **Which setup a new one starts from.** Options: most monitors shared, a tie to the one used
   last (pick); or always Desk. Gain: a setup with Home 27 starts from Home, which knows that
   monitor, not from Desk, which does not. Loss: the source can change as setups are added; the strip names it each time.
7. **Follow, or a frozen copy.** Ruled (owner, 2026-11-17 09:47 CST): follow the closest known
   setup until the owner makes a change on the new one. Frozen copy: not taken. Closest known setup
   is the setup sharing the most monitors; a tie goes to the one used last (coordinator default
   2026-11-17 11:47 CST, owner may change). Items 11 and 16 still name Desk in their examples.
   Decision `monitor-setups` (decisions/monitor-setups.md) holds what stays open.
8. **Autosave.** Ruled (owner, 2026-11-17 11:38 CST): autosave. Owner's word: "autosave". Every board
   edit is written straight away for the setup in use. Layouts have no Save or Revert. Undo still
   steps back moves. Replaces the mockup's pick. Loss: a test move is kept; Undo is the way back. Edits on Laptop + Portrait never write to Desk; replugging the ultrawide brings Desk
   back as it was (`bd-back`). Coordinator default 2026-11-17 11:47 CST, owner may change: Save stays
   for a scene's name and triggers only. The offline page (`file://`) cannot autosave: its edits stay
   in the page, and Apply downloads a place file, as today. A scene card shows `follows <setup>` while
   it follows, and `own layout` once any edit lands on this setup; the first edit is the switch. This
   replaces the mockup's Edited mark and its tag.
   Departs from: main, `app.html` `save` and `revert` buttons, for layouts.

## 3. Where the missing monitor's windows go

9. **Where the missing ultrawide's windows go.** Ruled (owner, 2026-11-17 09:47 CST), replacing
   the three options this item drew. The app remembers which windows were on the ultrawide, and their cells. While it
   is unplugged, those windows show in Windows That Stay Put as unplaced, so the owner can arrange a
   new layout for this setup. When the ultrawide comes back, they return to their remembered cells.
   The mockup's `fd-laptop`, `fd-portrait` and `fd-stay` states show the replaced options. Decision
   `monitor-setups` (decisions/monitor-setups.md) has the owner's words and what stays open. The reason text for an unplaced window is "Its screen is
   unplugged" (coordinator default 2026-11-17 11:47 CST, owner may change).
   Departs from: main, `tile.ps1`'s per-role loop, which skips a role with no screen ("No $role
   monitor. That part of the scene is skipped.") and lists its pins as missing. Owner grant: the
   ruling above.
10. **Fold select, dropped.** Coordinator default 2026-11-17 11:47 CST, owner may change. It follows
    from item 9's ruling, which folds nothing. No select in the strip, and no per-setup fold rule.

## 4. Showing the active setup

11. **The setup strip.** Options: a strip above the board (pick); or the top bar's crumb. The
    strip holds a small map, the setup's name, one sentence on the selected scene ("Default follows
    Desk until you change it"), and Monitors and Setups.
    Gain: it sits beside the board it describes (ux-control-beside-area) and has room for the
    sentence. Loss: about 56px of board height at 1440, two rows at 1024. At 1024,
    Monitors and Setups shows its icon only, with its name as title and label.
12. **No toast on a setup change.** Options: the strip alone (pick); or a toast as well. Gain:
    nothing covers the strip's select and button (at 1440 the toast did), and the change is said
    once. Loss: a change made while the app is open shows only as the strip and board changing.

## 5. Seeing, renaming and forgetting

13. **Monitors and Setups.** Options:
    - A dialog from the strip (`mg-dialog`, pick): Monitors (map, name, what Windows reports, a dot
      when plugged in or the date last seen, Forget) and Setups (map, name, its monitors, a dot when
      in use or the date last used, Forget). Windows' raw ID sits in a closed "What Windows calls
      it". Forget is off for a plugged-in monitor and the setup in use; a line under the lists says
      why, tied to each off button. Forget a setup removes its layouts from every scene, after a
      warning that names how many scenes had their own layout there; Forget a monitor also forgets
      each setup it is in. Gain: one place, out of the way of daily use. Loss: a setup not plugged
      in cannot be edited.
    - A Setups section in the left rail (`mg-rail`). A click shows that setup's layouts on the
      board, so a setup can be edited while unplugged. Loss: a fourth rail section, and at 1024 it
      pushes Categories off the strip.
14. **First run** (`mg-first`). The setup plugged in at the first launch after the update is the
    only one, and the list says what will fill it.
    Migration options: seed by shape (pick): the `wide` grid to a monitor wider than 2:1, `tall` to
    one taller than wide, `laptop` to the built-in screen. A first launch with the ultrawide
    unplugged gives the laptop its own grid, and the `wide` part's windows show as unplaced (item 9),
    so today's mix-up does not repeat. Or wait to seed until all three desk monitors are seen. Gain of the
    pick: works on day one. Loss: a monitor of the wrong shape at first launch takes a grid.
    Owner grant: yes.
15. **Naming setups.** Options: by their monitors, "Laptop + Portrait" (pick), renamed in the
    dialog; or by time ("Setup 3"). Gain: the name says what is plugged in. Loss: long with four
    monitors. The seeded one is named Desk.

## 6. The scene card

16. **Marker.** Options:
    - Icon (`cd-follow`, `cd-own`, pick): a link mark for "follows", a filled screen mark for "own
      layout", beside Built-in; a following scene's mini map draws its windows as dashed outlines.
      The word is in the mark's title and label, and the strip says it once for the selected scene
      (ux-label-once). Gain: no repeated words, and the card keeps today's height. Loss: the owner
      learns two small marks. Coordinator default 2026-11-17 11:47 CST, owner may change: the words are
      `follows <setup>` and `own layout`, and `Follow <setup> Again` stays on the scene card's menu.
      Whether the card shows the words, or only their title and label, is not ruled.
    - Word (`cd-word`): "Built-in · follows Desk" in the tag. Loss: the tag wraps to two or three
      lines beside Apply at both widths, so each card grows; and the word repeats on every card.

## 7. Triggers

17. **The count triggers.** Ruled (owner, 2026-11-17 09:47 CST): option a. Replace the `monitors`
    extra ("For N screens") with "Use This Scene on This Setup", with a setup select, and keep
    `noext` ("Laptop only"), a setup of one monitor. Keep both counts: not taken.
    Gain: Laptop + Portrait and Laptop + Home 27 can pick different scenes. Loss: a saved "For 3 screens" must map to a setup. Not drawn.
    Departs from: `decisions/triggers.md`, "A scene per monitor set. Pick the display scene whose
    monitor set matches." What was built counts screens (`app.html`, the `monitors` and `noext`
    extras). Owner grant: the ruling above.

## Open questions for the owner

- Item 4: should "When the Monitors Change" fire when the same monitors are only rearranged?
  Coordinator default, owner may change: no (decision `monitor-setups`).
- Item 7: ruled (owner, 2026-11-17 09:47 CST). Closest known setup and the Follow again control are
  coordinator defaults (2026-11-17 11:47 CST, decision `monitor-setups`). What the control links to is
  not ruled.
- Item 8: ruled (owner, 2026-11-17 11:38 CST): autosave. Save, the offline page and the card's words
  are coordinator defaults (2026-11-17 11:47 CST, decision `monitor-setups`).
- Item 9: ruled (owner, 2026-11-17 09:47 CST). The reason text is a coordinator default (2026-11-17
  11:47 CST, decision `monitor-setups`).
- Item 10: the fold select is dropped, a coordinator default (2026-11-17 11:47 CST, decision
  `monitor-setups`).
- Item 16: whether the card shows its words, or only their title and label, is not ruled (decision
  `monitor-setups`).
- Item 14: seed the first setup by shape. Coordinator default, owner may change (decision
  `monitor-setups`).
- Item 17: ruled (owner, 2026-11-17 09:47 CST): option a.
- From the critique: does the owner want to edit a setup that is not plugged in (the rail option),
  or only the one in use? Coordinator default, owner may change: only the one in use (decision
  `monitor-setups`).
