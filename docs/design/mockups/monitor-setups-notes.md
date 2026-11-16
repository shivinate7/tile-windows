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
bd-noid, fd-stay, cd-own), `-toast` (bd-new, bd-back), `-target` (fd-laptop, fd-portrait),
`-list` (fd-stay), `-dlg` (mg-dialog), `-setups` (mg-first, mg-rail), `-cards` (cd-follow,
cd-word), `-card` (cd-own).

Terms. A **setup** is the set of monitors plugged in at once. A scene's layout on a setup either
**follows** another setup (built from it, and kept in step with it) or is its **own layout**
(changed and saved on that setup). "Follows Desk" is the one phrase the screen uses for the first.

Everything not named below stays as it is on main: the board, tiles, stacks, the inspector's
Columns and Rows, Windows That Stay Put, Save and Revert.

## 1. Know each monitor by its hardware

1. **Identity.** A monitor is known by the maker, product code and serial that Windows reports
   (`WmiMonitorID`), and the built-in screen by its internal connection
   (`WmiMonitorConnectionParams`). Not by size rank.
   Gain: the laptop stays "Laptop" when the ultrawide is gone (`bd-new` against `bd-today`), and a
   different 27-inch at home is its own monitor, not "Ultrawide".
   Loss: a new data home for monitors and a WMI read on each monitor change.
   Unmeasured; the builder verifies: that a WMI monitor maps to a `Screen.DeviceName`, and how two
   identical monitors with no serial tell apart. Fallback: maker + product + the port it is on.
   Pick: hardware identity.
   Departs from: main, `tile.ps1` `Pick` and `Roles` (about lines 127-138), which give the widest
   screen the `wide` role, the tallest `tall`, and the smallest `laptop`; and `app.html` `ROLE` and
   `monName()`, which name a screen by that role. Owner grant: yes.
2. **Names.** A monitor seen for the first time is named by shape: Laptop (built-in), Ultrawide
   (wider than 2:1), Portrait (taller than wide), else "Monitor N". The owner renames it in the
   inspector's Monitor section (`Name` field, all states but `bd-today`) or in Monitors and Setups.
   Each name shows once per place on the board.
   Gain: today's three names stay for the owner's own desk, so nothing reads new on day one.
   Loss: none found.
3. **A monitor with no ID** (`bd-noid`). Windows gives no maker or serial for some monitors (an
   adapter, a TV). The strip turns amber and says the setup is not remembered; the scene follows
   the closest setup, and changes last until it is unplugged. One control leads on: Remember It
   by Its Size, which keys it by size and port. Pick: as drawn. Other option: remember it by size
   with no question. Loss of that: two hotel monitors of one size become one.

## 2. Setups and their layouts

4. **A setup is the set of monitors.** Its key is the sorted list of monitor IDs. Moving the same
   monitors around, or changing their scale, is the same setup; the board redraws at the new
   positions.
   Departs from: main, `tray.ps1` `Get-MonitorKey` (line 25), which keys on `DeviceName`, size and
   position, so a rearrange or a scale change counts as a change today.
   Open question: should "When the Monitors Change" still fire on a rearrange of the same monitors?
   Pick: no, it fires only when the setup changes. Owner grant: yes.
5. **Each scene keeps a layout per setup.** Grids, pins, zones, held cells and the fill screen
   are stored per setup, keyed by monitor ID.
   Departs from: main, `scenes.json`, where each scene's `grids`, `pins[].mon`, `zones[].mon`,
   `fill.mon` and `fill.held[].mon` name a role (`wide`, `tall`, `laptop`). Owner grant: yes.
6. **A new setup starts from the closest one seen.** Closest = most monitors shared; a tie goes to
   the one used last. Monitors still plugged in keep their grids and pins. The missing monitors'
   windows go where item 9 says.
7. **Follow, or a frozen copy.** Options:
   - Follow (pick): the new setup's layout stays linked to Desk. A later change to Desk reaches it,
     until the owner changes and saves the scene on the new setup; then it has its own layout.
     Follow Desk Again (`cd-own`) links it back.
     Gain: change Desk once and every setup that follows it keeps up. Loss: a change on Desk can
     move windows on another setup that the owner was not looking at.
   - Frozen copy: built once at first sight, never changed by Desk again. Gain: what you saw is
     what you get. Loss: a Desk change must be made again on each setup.
   Not drawn: the two differ only in the strip's words.
8. **Save stays.** An edit on a setup shows Edited, as today, and is kept for that setup only on
   Save (`app.html` Save and Revert). Edits on Laptop + Portrait never write to Desk; plugging the
   ultrawide back brings Desk as it was (`bd-back`).
   Open question, not blocking: the ask says "remember"; did the owner mean an edit is kept with no
   Save? Pick: keep Save.

## 3. Where the missing monitor's windows go

9. **Options, one per state** (Default has seven windows on the ultrawide):
   - Fold onto the laptop (`fd-laptop`, pick). They go to the remaining monitor closest in shape
     (landscape to landscape). Its grid grows to 2×2: its own window keeps cell 1, and each
     category of folded window takes one cell, stacked in the scene's fill order (Claude +2 behind
     Claude; File Explorer behind Excel).
     Gain: every window has a place, and like windows stay together. Loss: four windows wait
     behind others; the stack badge names them.
   - Fold onto the portrait (`fd-portrait`). The larger monitor by area: 1×2 grows to 1×5. Gain:
     more pixels. Loss: wide apps in short rows, and mail and chat lose half their height.
   - Send to Windows That Stay Put (`fd-stay`). The ultrawide's part of the scene waits; its windows
     stay where Windows left them, listed as "Its screen is unplugged". Gain: nothing moves that the
     owner did not place. Loss: seven windows piled on the laptop by Windows itself.
   The fill follows the windows: in `fd-laptop` the laptop now "fills".
10. **The owner can change it per setup.** The strip has a select, "Ultrawide's windows go to",
    with Laptop, Portrait and Windows That Stay Put. It shows only while a monitor of the source
    setup is missing. A change rebuilds the scenes that follow, not those with their own layout.

## 4. Showing the active setup

11. **The setup strip** sits above the board it describes: a small map of the setup, its name, one
    sentence on the selected scene ("Default follows Desk until you change it and Save"), the fold
    select, and Monitors and Setups. Options: in the top bar's crumb (Scene: Default · Setup: …).
    Loss of the crumb: no room for the sentence or the select at 1024. Pick: the strip.
12. **A toast on change** (`bd-new`, `bd-back`): "Screens changed: Laptop + Portrait, a new
    setup." It names the change once; the strip holds it after the toast closes. Loss: at 1440 the
    toast covers the strip's fold select and Monitors and Setups while it shows (critique finding,
    kept: the toast closes, and today's toast sits in the same place, `app.html` `.toast`).
    At 1024, Monitors and Setups shows its icon only, with its name as the title and label, so
    the strip stays two rows.
13. **Windows move only by Apply or a trigger.** A setup change redraws the board. Windows move
    when the owner presses Apply, or when the "When the Monitors Change" trigger applies a scene,
    as today (`decisions/triggers.md`).

## 5. Seeing, renaming and forgetting

14. **Monitors and Setups** (`mg-dialog`, pick). One dialog from the strip: Monitors (map, name
    field, what Windows reports, Plugged in or Last seen, Forget) and Setups (map, name field,
    its monitors, how many scenes have their own layout, In use or Last used, Forget). Windows'
    raw ID sits in a closed "What Windows calls it". A plugged-in monitor and the setup in use
    cannot be forgotten, and say why on hover and focus. Forget a setup removes its layouts from
    every scene; Forget a monitor also forgets each setup it is in, after a warning that counts them.
    Other option: a Setups section in the left rail (`mg-rail`); a click shows that setup's layouts
    on the board, so the owner can edit a setup that is not plugged in. Loss: a fourth rail section,
    and at 1024 it pushes Categories off the strip. Pick: the dialog.
15. **First run** (`mg-first`). The setup plugged in at the first launch after the update becomes
    the only setup, and the list says what will fill it.
    Migration: today's role grids go to monitors by shape, not rank: the `wide` grid to a monitor
    wider than 2:1, `tall` to one taller than wide, `laptop` to the built-in screen. So a first
    launch with the ultrawide unplugged gives the laptop its own grid, and the `wide` part waits
    for an ultrawide, folded as item 9 says. It does not repeat today's mix-up.
    Open question: is shape enough to seed, or should the app wait to seed until it sees all three
    of the desk's monitors? Owner grant: yes.
16. **Naming setups.** A new setup is named by its monitors ("Laptop + Portrait"); the owner
    renames it in the dialog. The seeded one is named Desk.

## 6. The scene card

17. **Marker.** Options:
    - Icon (`cd-follow`, `cd-own`, pick): a link mark for "follows", a filled screen mark for "own
      layout", beside Built-in; a following scene's mini map draws its windows as dashed outlines.
      The word is in the mark's title and label, and the strip says it once for the selected scene
      (rule ux-label-once).
    - Word (`cd-word`): "Built-in · follows Desk" in the tag. Loss: the tag wraps to two or three
      lines beside Apply at both widths, so each card grows; and the word repeats on every card.
18. **Edited and unsaved** keeps today's Edited dot in the top bar and "· edited" in the tag.

## 7. Triggers

19. **The count triggers.** Departs from: `decisions/triggers.md`, "A scene per monitor set. Pick
    the display scene whose monitor set matches." What was built counts screens: the `monitors`
    extra ("For N screens") and `noext` ("Laptop only") in `app.html`. A count cannot tell
    Laptop + Portrait from Laptop + Home 27.
    Proposal, not drawn: the `monitors` extra becomes "Use This Scene on This Setup", with a setup
    select; `noext` stays as is, since Laptop Only is a setup of one monitor. Owner grant: yes.

## Open questions for the owner

- Item 4: should "When the Monitors Change" fire when the same monitors are only rearranged?
- Item 7: follow (pick) or frozen copy?
- Item 8: keep Save, or remember edits with no Save?
- Item 9: fold onto the laptop (pick), onto the portrait, or send to Windows That Stay Put?
- Item 15: seed the first setup from today's role grids by shape (pick), or wait for all three
  desk monitors?
- Item 19: replace "For N screens" with "Use This Scene on This Setup"?
